import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 本地图像处理服务（与 UI 解耦）。
///
/// 设计要点：
/// - 以 `actor` 实现，确保抠图等耗时操作天然运行在后台、避免阻塞主线程，且并发安全。
/// - 核心管线全部基于跨平台的 `CGImage` / `Data`（ImageIO + Vision + CoreImage），
///   因此同一份代码可在 iOS 17+ 与 macOS 14+ 编译运行，不直接依赖 UIImage / NSImage。
/// - 输入：相册选图得到的原始 `Data`；输出：带透明背景的 PNG `Data`，可直接存入 SwiftData。
actor VisionService {
    /// 全局单例。
    static let shared = VisionService()

    private let ciContext = CIContext()

    private init() {}

    /// 处理过程中可能出现的错误，均带中文文案，便于 UI 直接展示。
    enum VisionServiceError: LocalizedError {
        case invalidImageData
        case noForegroundDetected
        case maskGenerationFailed
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImageData:     return "无法解析所选图片数据。"
            case .noForegroundDetected: return "未能识别到衣物主体，请换一张主体清晰、背景简单的图片。"
            case .maskGenerationFailed: return "生成抠图蒙版失败，请重试。" + Self.simulatorHint
            case .encodingFailed:       return "抠图结果编码失败。"
            }
        }

        /// 在模拟器上，Vision 前景抠图常因缺少 ML 推理后端而失败，提示改用真机。
        private static var simulatorHint: String {
            #if targetEnvironment(simulator)
            return "（模拟器可能不支持本地抠图，建议用真机测试。）"
            #else
            return ""
            #endif
        }
    }

    /// 对输入图片执行本地抠图（去背），返回带透明通道的 PNG 数据。
    ///
    /// 调用 `VNGenerateForegroundInstanceMaskRequest` 提取前景主体实例，
    /// 再用观察结果生成「仅保留主体、背景透明」的图像。
    /// - Parameter imageData: 原始图片二进制（来自 PhotosPicker）。
    /// - Returns: 去背后的 PNG 数据。
    func removeBackground(from imageData: Data) async throws -> Data {
        guard let cgImage = Self.makeCGImage(from: imageData) else {
            throw VisionServiceError.invalidImageData
        }
        // 读取 EXIF 方向并交给 Vision，保证输出主体为正向。
        let orientation = Self.orientation(from: imageData)

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("⚠️ VisionService perform 失败: \(error)")
            throw VisionServiceError.maskGenerationFailed
        }

        // 取首个观察结果，其包含所有被识别为前景的实例。
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw VisionServiceError.noForegroundDetected
        }

        // 生成「所有前景实例」合成的去背图（裁剪到主体外接框，得到更干净的卡片图）。
        let maskedPixelBuffer: CVPixelBuffer
        do {
            maskedPixelBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
        } catch {
            print("⚠️ VisionService generateMaskedImage 失败: \(error)")
            throw VisionServiceError.maskGenerationFailed
        }

        // CVPixelBuffer(RGBA) → CGImage → PNG（保留 Alpha 透明通道）。
        let ciImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
        guard let outputCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw VisionServiceError.maskGenerationFailed
        }
        guard let pngData = Self.pngData(from: outputCGImage) else {
            throw VisionServiceError.encodingFailed
        }
        return pngData
    }

    // MARK: - CoreImage 主辅色提取

    /// 从图片中提取主色（占比最高）与辅色（占比次高且与主色差异明显）。
    ///
    /// 建议传入已抠图（透明背景）的数据，背景透明像素会被跳过，从而只统计衣物本体颜色。
    /// 失败时返回中性灰主色、无辅色，绝不抛错（取色非关键路径）。
    func extractColors(from imageData: Data) async -> (dominant: StoredColor, secondary: StoredColor?) {
        let fallback = StoredColor(red: 0.5, green: 0.5, blue: 0.5)
        guard let cgImage = Self.makeCGImage(from: imageData),
              let pixels = Self.sampleRGBA(cgImage, size: 48) else {
            return (fallback, nil)
        }

        // 将像素量化到 6×6×6 的颜色桶并累计均值，统计占比。
        let levels = 6
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var index = 0
        while index < pixels.count {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2], a = pixels[index + 3]
            index += 4
            if a < 32 { continue } // 跳过透明背景
            let rk = Int(r) * levels / 256
            let gk = Int(g) * levels / 256
            let bk = Int(b) * levels / 256
            let key = (rk * levels + gk) * levels + bk
            var entry = buckets[key] ?? (count: 0, r: 0, g: 0, b: 0)
            entry.count += 1
            entry.r += Double(r); entry.g += Double(g); entry.b += Double(b)
            buckets[key] = entry
        }

        guard !buckets.isEmpty else { return (fallback, nil) }
        let sorted = buckets.values.sorted { $0.count > $1.count }

        func averageColor(_ e: (count: Int, r: Double, g: Double, b: Double)) -> StoredColor {
            StoredColor(
                red: e.r / Double(e.count) / 255,
                green: e.g / Double(e.count) / 255,
                blue: e.b / Double(e.count) / 255
            )
        }

        let dominant = averageColor(sorted[0])
        // 辅色：第一个与主色 RGB 曼哈顿距离足够大的桶。
        var secondary: StoredColor?
        for entry in sorted.dropFirst() {
            let c = averageColor(entry)
            let distance = abs(c.red - dominant.red) + abs(c.green - dominant.green) + abs(c.blue - dominant.blue)
            if distance > 0.25 { secondary = c; break }
        }
        return (dominant, secondary)
    }

    // MARK: - 跨平台图像工具（基于 ImageIO / CoreGraphics，无 UIKit / AppKit 依赖）

    /// 将图片缩放绘制到 size×size 的 RGBA8 位图并返回像素数组（用于取色采样）。
    private static func sampleRGBA(_ cgImage: CGImage, size: Int) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var data = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        return data
    }

    /// 从图片二进制解码出 `CGImage`。
    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 读取图片的 EXIF 方向，默认为 `.up`。
    private static func orientation(from data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return .up
        }
        return orientation
    }

    /// 将 `CGImage` 编码为 PNG（保留透明通道）。
    private static func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
