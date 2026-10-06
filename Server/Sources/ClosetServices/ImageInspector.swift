import Foundation
import ClosetStorage

/// 从文件头读取图片格式与尺寸，不解码像素，任何平台都可用。
///
/// 用于上传校验：格式按文件头判断，不信任文件名或客户端声明的类型；尺寸用于像素上限检查。
public enum ImageInspector {
    public struct Info: Sendable, Equatable {
        public var format: ImageFormat
        public var width: Int
        public var height: Int

        public init(format: ImageFormat, width: Int, height: Int) {
            self.format = format
            self.width = width
            self.height = height
        }
    }

    /// 读取格式与尺寸。格式无法识别或读不出尺寸时返回 nil。
    public static func inspect(_ data: Data) -> Info? {
        let bytes = [UInt8](data)
        let format = ImageFormat.detect(data)
        let size: (Int, Int)?
        switch format {
        case .png: size = pngSize(bytes)
        case .jpeg: size = jpegSize(bytes)
        case .webp: size = webpSize(bytes)
        case .heic, .heif, .avif: size = isoBoxSize(bytes)
        default: size = nil
        }
        guard let (width, height) = size, width > 0, height > 0 else { return nil }
        return Info(format: format, width: width, height: height)
    }

    // MARK: - 字节读取

    private static func be16(_ b: [UInt8], _ i: Int) -> Int? {
        guard i >= 0, i + 2 <= b.count else { return nil }
        return Int(b[i]) << 8 | Int(b[i + 1])
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int? {
        guard i >= 0, i + 4 <= b.count else { return nil }
        return Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> Int? {
        guard i >= 0, i + 2 <= b.count else { return nil }
        return Int(b[i]) | Int(b[i + 1]) << 8
    }

    private static func le24(_ b: [UInt8], _ i: Int) -> Int? {
        guard i >= 0, i + 3 <= b.count else { return nil }
        return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16
    }

    private static func ascii(_ b: [UInt8], _ i: Int, _ n: Int) -> String? {
        guard i >= 0, i + n <= b.count else { return nil }
        return String(bytes: b[i..<(i + n)], encoding: .ascii)
    }

    // MARK: - PNG：IHDR 必须是第一个块

    private static func pngSize(_ b: [UInt8]) -> (Int, Int)? {
        guard ascii(b, 12, 4) == "IHDR", let w = be32(b, 16), let h = be32(b, 20) else { return nil }
        return (w, h)
    }

    // MARK: - JPEG：逐段查找帧头（SOFn）

    private static func jpegSize(_ b: [UInt8]) -> (Int, Int)? {
        var i = 2
        while i + 1 < b.count {
            guard b[i] == 0xFF else { return nil }
            var marker = b[i + 1]
            i += 2
            while marker == 0xFF, i < b.count { marker = b[i]; i += 1 }  // 填充字节
            switch marker {
            case 0xD8, 0x01, 0xD0...0xD7:
                continue  // 没有长度字段的标记
            case 0xD9, 0xDA:
                return nil  // 图像结束或扫描开始之前仍未找到帧头
            default:
                guard let length = be16(b, i), length >= 2 else { return nil }
                let isFrameHeader = (0xC0...0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker)
                if isFrameHeader {
                    guard let h = be16(b, i + 3), let w = be16(b, i + 5) else { return nil }
                    return (w, h)
                }
                i += length
            }
        }
        return nil
    }

    // MARK: - WebP：VP8、VP8L、VP8X 三种块

    private static func webpSize(_ b: [UInt8]) -> (Int, Int)? {
        switch ascii(b, 12, 4) {
        case "VP8 ":
            // 帧标签 3 字节，起始码 9D 01 2A，随后是 14 位宽高。
            guard b.count >= 30, b[23] == 0x9D, b[24] == 0x01, b[25] == 0x2A,
                  let w = le16(b, 26), let h = le16(b, 28) else { return nil }
            return (w & 0x3FFF, h & 0x3FFF)
        case "VP8L":
            guard b.count >= 25, b[20] == 0x2F else { return nil }
            let bits = Int(b[21]) | Int(b[22]) << 8 | Int(b[23]) << 16 | Int(b[24]) << 24
            return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        case "VP8X":
            guard let w = le24(b, 24), let h = le24(b, 27) else { return nil }
            return (w + 1, h + 1)
        default:
            return nil
        }
    }

    // MARK: - HEIC、HEIF、AVIF：meta / iprp / ipco 中的 ispe 属性

    /// 取全部 ispe 中最大的宽高。网格图片的主图 ispe 是完整尺寸，各分块更小，所以最大值就是图片尺寸。
    private static func isoBoxSize(_ b: [UInt8]) -> (Int, Int)? {
        var best: (Int, Int)?
        func visit(_ start: Int, _ end: Int, depth: Int) {
            guard depth < 6 else { return }
            var i = start
            while i + 8 <= end {
                guard var size = be32(b, i), let type = ascii(b, i + 4, 4) else { return }
                var header = 8
                if size == 1 {
                    guard let high = be32(b, i + 8), let low = be32(b, i + 12) else { return }
                    size = high << 32 | low
                    header = 16
                } else if size == 0 {
                    size = end - i
                }
                guard size >= header, i + size <= end else { return }
                switch type {
                case "meta":
                    visit(i + header + 4, i + size, depth: depth + 1)  // 完整盒子：跳过版本与标志
                case "iprp", "ipco":
                    visit(i + header, i + size, depth: depth + 1)
                case "ispe":
                    if let w = be32(b, i + header + 4), let h = be32(b, i + header + 8), w > 0, h > 0 {
                        if best == nil || w * h > best!.0 * best!.1 { best = (w, h) }
                    }
                default:
                    break
                }
                i += size
            }
        }
        visit(0, b.count, depth: 0)
        return best
    }
}
