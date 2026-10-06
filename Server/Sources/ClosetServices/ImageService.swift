import Foundation
import ClosetCore
import ClosetStorage

/// 一张已上传并通过校验的图片。
public struct UploadedImage: Sendable, Equatable {
    public var ref: MediaRef
    public var width: Int
    public var height: Int

    public init(ref: MediaRef, width: Int, height: Int) {
        self.ref = ref
        self.width = width
        self.height = height
    }
}

/// 一张原图的处理结果，对应 App 中 `ItemDraftModel.ingest` 的产出。
public struct ProcessedImage: Sendable {
    public var original: MediaRef
    /// 抠图结果（PNG）。平台不支持或抠图失败时为 nil，与 App 相同，此时仍可保存。
    public var processed: MediaRef?
    /// 提取的主辅色。平台不支持取色时为 nil，主色需要用户手动选择。
    public var colors: (dominant: StoredColor, secondary: StoredColor?)?
    /// 抠图失败时的提示，文案来自 App 的 `VisionService`。
    public var failure: String?
}

/// 图片上传、处理、派生图与相似检测。
public struct ImageService: Sendable {
    /// 单张图片的大小上限。
    public static let maxUploadBytes = 50 * 1024 * 1024
    /// 像素总数上限，防止解码时占用过多内存。
    public static let maxPixels = 100_000_000
    /// 接受的格式。SVG 等可以携带脚本的格式一律拒绝。
    public static let acceptedFormats: [ImageFormat] = [.jpeg, .png, .heic, .heif, .webp]
    /// 列表缩略图的长边。
    public static let thumbnailPixelSize = 512
    /// 格式转换后展示图的长边。
    public static let displayPixelSize = 2048

    let store: ClosetStore
    let processor: any ImageProcessor
    let now: @Sendable () -> Date

    public init(store: ClosetStore, processor: any ImageProcessor, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.processor = processor
        self.now = now
    }

    public var capabilities: ImageCapabilities { processor.capabilities }

    /// 校验并保存一张上传的图片。原图按收到的字节原样保存（决策 D4 待定，与 App 相同）。
    public func upload(_ data: Data) async throws -> UploadedImage {
        guard !data.isEmpty else { throw ServiceError.invalid("图片内容为空。") }
        guard data.count <= Self.maxUploadBytes else {
            throw ServiceError.invalid("图片超过 \(Self.maxUploadBytes / 1024 / 1024) MB 上限。")
        }
        let format = ImageFormat.detect(data)
        guard Self.acceptedFormats.contains(format) else {
            throw ServiceError.invalid("不支持的文件类型。只接受 JPEG、PNG、HEIC、HEIF 与 WebP 图片。")
        }
        guard let info = ImageInspector.inspect(data) else {
            throw ServiceError.invalid("无法读取图片尺寸，文件可能已损坏。")
        }
        guard info.width * info.height <= Self.maxPixels else {
            throw ServiceError.invalid("图片像素过多（\(info.width)×\(info.height)），上限为 1 亿像素。")
        }
        let ref = MediaRef(sha256: MediaStore.sha256Hex(data), format: format, byteCount: data.count)
        // 先登记再写文件：垃圾回收只删除没有登记的文件，这样写入过程中不会被误删。
        let time = now()
        try await store.transaction { try $0.recordUpload(ref, at: time) }
        try store.media.write(data)
        return UploadedImage(ref: ref, width: info.width, height: info.height)
    }

    /// 读取图片文件。
    public func data(of ref: MediaRef) throws -> Data {
        try store.media.read(ref)
    }

    /// 查找一张已登记的图片。
    public func media(sha256: String) async throws -> MediaRef {
        guard sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              let ref = try await store.read({ try $0.media(sha256: sha256) }) else {
            throw ServiceError.notFound("未找到这张图片。")
        }
        return ref
    }

    /// 抠图与取色，流程与 App 的 `ItemDraftModel.ingest` 相同：
    /// 抠图成功时从抠图结果取色；抠图失败时回退到原图取色，仍可保存。
    public func process(sha256: String) async throws -> ProcessedImage {
        let original = try await media(sha256: sha256)
        let data = try store.media.read(original)
        guard processor.capabilities.backgroundRemoval else {
            return ProcessedImage(original: original, processed: nil, colors: await processor.extractColors(from: data), failure: nil)
        }
        do {
            let png = try await processor.removeBackground(from: data)
            let processed = MediaRef(sha256: MediaStore.sha256Hex(png), format: ImageFormat.detect(png), byteCount: png.count)
            let time = now()
            try await store.transaction { try $0.recordUpload(processed, at: time) }
            try store.media.write(png)
            return ProcessedImage(original: original, processed: processed, colors: await processor.extractColors(from: png), failure: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return ProcessedImage(original: original, processed: nil, colors: await processor.extractColors(from: data), failure: message)
        }
    }

    /// 实际要发送给浏览器的图片：需要时生成并缓存派生图，无法生成时返回原图。
    public func servable(_ ref: MediaRef, kind: MediaVariantKind) async throws -> MediaRef {
        let needsConversion = !ref.format.isBrowserDisplayable
        guard processor.capabilities.formatConversion, kind == .thumbnail || needsConversion else { return ref }
        if let cached = try await store.read({ try $0.variant(of: ref.sha256, kind: kind) }) { return cached }
        let size = kind == .thumbnail ? Self.thumbnailPixelSize : Self.displayPixelSize
        guard let derived = await processor.makeDerivedImage(from: try store.media.read(ref), maxPixelSize: size) else { return ref }
        let variant = MediaRef(sha256: MediaStore.sha256Hex(derived), format: ImageFormat.detect(derived), byteCount: derived.count)
        try await store.transaction { try $0.insertVariant(of: ref.sha256, kind: kind, variant: variant) }
        try store.media.write(derived)
        return variant
    }

    /// 相似单品检测，输入与 App 的 `DuplicationView` 相同：全部单品按录入时间倒序，优先使用抠图结果。
    public func similarGroups() async throws -> [[StoredItem]] {
        guard processor.capabilities.similarityDetection else {
            throw ServiceError.conflict("当前平台不支持相似单品检测。")
        }
        let items = try await store.read { try $0.items() }
        let inputs = items.map { item in
            SimilarityInput(id: item.id, imageData: item.displayImage.flatMap { try? store.media.read($0) }, color: item.dominantColor)
        }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return await processor.similarGroups(inputs).map { $0.compactMap { byID[$0] } }.filter { $0.count >= 2 }
    }
}
