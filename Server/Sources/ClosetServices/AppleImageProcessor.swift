#if canImport(Vision) && canImport(ImageIO)
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ClosetCore
import ClosetImaging

/// macOS 上的图片处理：抠图、取色与相似检测直接调用 App 的 `VisionService` 与 `DuplicationDetectorService`，
/// 与 App 编译的是同一份源文件；派生图用 ImageIO 生成。
public struct AppleImageProcessor: ImageProcessor {
    public init() {}

    public var capabilities: ImageCapabilities {
        ImageCapabilities(backgroundRemoval: true, colorExtraction: true, formatConversion: true, similarityDetection: true)
    }

    public func removeBackground(from data: Data) async throws -> Data {
        try await VisionService.shared.removeBackground(from: data)
    }

    public func extractColors(from data: Data) async -> (dominant: StoredColor, secondary: StoredColor?)? {
        await VisionService.shared.extractColors(from: data)
    }

    public func makeDerivedImage(from data: Data, maxPixelSize: Int) async -> Data? {
        Self.derivedImage(from: data, maxPixelSize: maxPixelSize)
    }

    public func similarGroups(_ inputs: [SimilarityInput]) async -> [[UUID]] {
        await DuplicationDetectorService.shared.findSimilarGroups(inputs.map {
            DuplicationDetectorService.ItemFingerprintInput(id: $0.id, imageData: $0.imageData, color: $0.color)
        })
    }

    /// 按 EXIF 方向转正并缩放，带透明通道的编码为 PNG，其余编码为 JPEG。只写入像素，不复制原图的元数据。
    static func derivedImage(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let output = NSMutableData()
        let type = hasAlpha ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
#endif
