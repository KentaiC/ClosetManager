import Foundation
import ClosetCore
import ClosetStorage
@testable import ClosetServices

/// 按格式规范拼出的最小文件头，只用于尺寸解析与上传校验。
enum SampleImages {
    static func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func le24(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF)] }
    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        var bytes = be32(8 + payload.count)
        bytes += Array(type.utf8)
        bytes += payload
        return bytes
    }

    static func png(width: Int, height: Int) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += be32(13)
        bytes += Array("IHDR".utf8)
        bytes += be32(width)
        bytes += be32(height)
        bytes += [8, 6, 0, 0, 0, 0, 0, 0, 0]
        return Data(bytes)
    }

    /// SOI、APP1（EXIF 占位）、DQT，然后是给定类型的帧头。
    static func jpeg(width: Int, height: Int, frameMarker: UInt8 = 0xC0) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8]
        bytes += [0xFF, 0xE1] as [UInt8]
        bytes += be16(2 + 6)
        bytes += Array("Exif".utf8)
        bytes += [0, 0] as [UInt8]
        bytes += [0xFF, 0xDB] as [UInt8]
        bytes += be16(2 + 3)
        bytes += [0, 1, 2] as [UInt8]
        bytes += [0xFF, frameMarker]
        bytes += be16(2 + 6)
        bytes += [8] as [UInt8]
        bytes += be16(height)
        bytes += be16(width)
        bytes += [3, 0xFF, 0xD9] as [UInt8]
        return Data(bytes)
    }

    static func webpLossy(width: Int, height: Int) -> Data {
        var frame: [UInt8] = [0, 0, 0, 0x9D, 0x01, 0x2A]
        frame += le16(width)
        frame += le16(height)
        return riff(chunk: "VP8 ", frame)
    }

    static func webpLossless(width: Int, height: Int) -> Data {
        let bits: Int = (width - 1) | (height - 1) << 14
        let payload: [UInt8] = [0x2F, UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)]
        return riff(chunk: "VP8L", payload)
    }

    static func webpExtended(width: Int, height: Int) -> Data {
        var payload: [UInt8] = [0, 0, 0, 0]
        payload += le24(width - 1)
        payload += le24(height - 1)
        return riff(chunk: "VP8X", payload)
    }

    private static func riff(chunk: String, _ payload: [UInt8]) -> Data {
        var body: [UInt8] = Array("WEBP".utf8)
        body += Array(chunk.utf8)
        body += [UInt8(payload.count & 0xFF), 0, 0, 0]
        body += payload
        var bytes: [UInt8] = Array("RIFF".utf8)
        bytes += [UInt8(body.count & 0xFF), UInt8(body.count >> 8 & 0xFF), 0, 0]
        bytes += body
        return Data(bytes)
    }

    /// ftyp 加 meta（完整盒子）/iprp/ipco，ipco 中先放分块尺寸，再放主图尺寸，模拟 iPhone 的网格 HEIC。
    static func heic(width: Int, height: Int, brand: String = "heic") -> Data {
        let zero: [UInt8] = [0, 0, 0, 0]
        let ftyp = box("ftyp", Array(brand.utf8) + zero + Array("mif1".utf8) + Array(brand.utf8))
        let tile = box("ispe", zero + be32(512) + be32(512))
        let full = box("ispe", zero + be32(width) + be32(height))
        let hdlr = box("hdlr", zero + zero + Array("pict".utf8) + [UInt8](repeating: 0, count: 13))
        let properties = box("iprp", box("ipco", tile + full))
        let meta = box("meta", zero + hdlr + properties)
        let mdat = box("mdat", [1, 2, 3])
        return Data(ftyp + meta + mdat)
    }
}

/// 用来代替 macOS 图像框架的替身，记录调用次数。
final class FakeImageProcessor: ImageProcessor, @unchecked Sendable {
    struct Failure: LocalizedError { var errorDescription: String? { "未能识别到衣物主体，请换一张主体清晰、背景简单的图片。" } }

    let capabilities: ImageCapabilities
    var failRemoval = false
    var groups: [[UUID]] = []
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(capabilities: ImageCapabilities = ImageCapabilities(backgroundRemoval: true, colorExtraction: true, formatConversion: true, similarityDetection: true)) {
        self.capabilities = capabilities
    }

    func calls(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    private func count(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }

    /// 抠图结果：一个与输入长度相关的 PNG 文件头，保证不同输入得到不同内容。
    static func cutout(for data: Data) -> Data { SampleImages.png(width: 10 + data.count % 50, height: 20) }
    static let processedColor = StoredColor(red: 0.9, green: 0.1, blue: 0.1)
    static let originalColor = StoredColor(red: 0.1, green: 0.1, blue: 0.9)

    func removeBackground(from data: Data) async throws -> Data {
        count("removeBackground")
        if failRemoval { throw Failure() }
        return Self.cutout(for: data)
    }

    func extractColors(from data: Data) async -> (dominant: StoredColor, secondary: StoredColor?)? {
        count("extractColors")
        return ImageFormat.detect(data) == .png && data.count < 40 ? (Self.processedColor, nil) : (Self.originalColor, StoredColor(red: 0, green: 0, blue: 0))
    }

    func makeDerivedImage(from data: Data, maxPixelSize: Int) async -> Data? {
        count("makeDerivedImage-\(maxPixelSize)")
        return SampleImages.jpeg(width: maxPixelSize, height: maxPixelSize / 2)
    }

    func similarGroups(_ inputs: [SimilarityInput]) async -> [[UUID]] {
        count("similarGroups")
        return groups
    }
}
