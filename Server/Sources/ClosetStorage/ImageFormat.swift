import Foundation

/// 按文件头识别的图片格式。不依赖扩展名或客户端声明的类型。
public enum ImageFormat: String, Codable, Sendable, CaseIterable {
    case png, jpeg, gif, webp, heic, heif, avif, tiff, bmp
    /// 无法识别，可能不是图片。
    case unknown

    public static func detect(_ data: Data) -> ImageFormat {
        let bytes = [UInt8](data.prefix(32))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.count >= prefix.count && Array(bytes[0..<prefix.count]) == prefix }
        func ascii(_ range: Range<Int>) -> String? {
            guard bytes.count >= range.upperBound else { return nil }
            return String(bytes: bytes[range], encoding: .ascii)
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return .gif }
        if ascii(0..<4) == "RIFF", ascii(8..<12) == "WEBP" { return .webp }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if starts([0x42, 0x4D]) { return .bmp }
        if ascii(4..<8) == "ftyp", let brand = ascii(8..<12) {
            switch brand {
            case "heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs": return .heic
            case "mif1", "msf1": return .heif
            case "avif", "avis": return .avif
            default: return .unknown
            }
        }
        return .unknown
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .unknown: return "bin"
        default: return rawValue
        }
    }

    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .gif: return "image/gif"
        case .webp: return "image/webp"
        case .heic: return "image/heic"
        case .heif: return "image/heif"
        case .avif: return "image/avif"
        case .tiff: return "image/tiff"
        case .bmp: return "image/bmp"
        case .unknown: return "application/octet-stream"
        }
    }

    /// 主流浏览器可以直接用 `<img>` 显示的格式。HEIC、HEIF、TIFF 只有部分浏览器支持。
    public var isBrowserDisplayable: Bool {
        switch self {
        case .png, .jpeg, .gif, .webp, .avif, .bmp: return true
        case .heic, .heif, .tiff, .unknown: return false
        }
    }
}
