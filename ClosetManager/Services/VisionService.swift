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
            case .maskGenerationFailed: return "生成抠图蒙版失败，请重试。"
            case .encodingFailed:       return "抠图结果编码失败。"
            }
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

    // MARK: - 跨平台图像工具（基于 ImageIO / CoreGraphics，无 UIKit / AppKit 依赖）

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
