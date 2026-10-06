import Foundation
import ClosetCore

/// 当前平台具备的图片处理能力。
public struct ImageCapabilities: Sendable, Equatable, Codable {
    /// 本地抠图。
    public var backgroundRemoval: Bool
    /// 从图片中提取主辅色。
    public var colorExtraction: Bool
    /// 把浏览器无法显示的格式（如 HEIC）转换为可显示的版本，并生成缩略图。
    public var formatConversion: Bool
    /// 相似单品检测。
    public var similarityDetection: Bool

    public init(backgroundRemoval: Bool, colorExtraction: Bool, formatConversion: Bool, similarityDetection: Bool) {
        self.backgroundRemoval = backgroundRemoval
        self.colorExtraction = colorExtraction
        self.formatConversion = formatConversion
        self.similarityDetection = similarityDetection
    }

    public static let none = ImageCapabilities(
        backgroundRemoval: false, colorExtraction: false, formatConversion: false, similarityDetection: false)
}

/// 相似检测的一件输入。
public struct SimilarityInput: Sendable {
    public var id: UUID
    public var imageData: Data?
    public var color: StoredColor

    public init(id: UUID, imageData: Data?, color: StoredColor) {
        self.id = id
        self.imageData = imageData
        self.color = color
    }
}

/// 依赖平台图像框架的处理。业务流程在 `ImageService` 中，与平台无关。
public protocol ImageProcessor: Sendable {
    var capabilities: ImageCapabilities { get }

    /// 抠图，返回带透明背景的 PNG。
    func removeBackground(from data: Data) async throws -> Data

    /// 提取主辅色。不支持取色的平台返回 nil。
    func extractColors(from data: Data) async -> (dominant: StoredColor, secondary: StoredColor?)?

    /// 生成浏览器可以显示的派生图，长边不超过 `maxPixelSize`，不带原图元数据。无法生成时返回 nil。
    func makeDerivedImage(from data: Data, maxPixelSize: Int) async -> Data?

    /// 找出相似组，每组至少两件。
    func similarGroups(_ inputs: [SimilarityInput]) async -> [[UUID]]
}

/// 没有图像框架的平台（如 Linux）：上传与校验照常进行，但不做抠图、取色、转换与相似检测。
public struct UnavailableImageProcessor: ImageProcessor {
    public init() {}

    public var capabilities: ImageCapabilities { .none }

    public func removeBackground(from data: Data) async throws -> Data {
        throw ServiceError.conflict("当前平台不支持本地抠图。")
    }

    public func extractColors(from data: Data) async -> (dominant: StoredColor, secondary: StoredColor?)? { nil }

    public func makeDerivedImage(from data: Data, maxPixelSize: Int) async -> Data? { nil }

    public func similarGroups(_ inputs: [SimilarityInput]) async -> [[UUID]] { [] }
}

public enum ImageProcessors {
    /// 当前平台可用的实现：macOS 上使用 App 的 Vision 与 ImageIO 代码，其它平台不提供图片处理。
    public static var platformDefault: any ImageProcessor {
        #if canImport(Vision) && canImport(ImageIO)
        return AppleImageProcessor()
        #else
        return UnavailableImageProcessor()
        #endif
    }
}
