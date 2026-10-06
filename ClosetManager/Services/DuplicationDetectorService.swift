import Foundation
import Vision
import CoreGraphics
import ImageIO

/// 本地相似单品检测（actor，后台执行；绝不在录入时自动跑，只作手动工具）。
///
/// 原理：用 `VNGenerateImageFeaturePrintRequest` 为每张图算「特征指纹」(`VNFeaturePrintObservation`)，
/// 两两用 `computeDistance` 求视觉距离（越小越像），再结合主色距离做二次确认，
/// 把同时满足两个阈值的单品用并查集聚成相似组。
actor DuplicationDetectorService {
    static let shared = DuplicationDetectorService()
    private init() {}

    /// 传入的可 Sendable 输入（避免把 @Model 跨 actor 传递）。
    struct ItemFingerprintInput: Sendable {
        let id: UUID
        let imageData: Data?
        let color: StoredColor
    }

    /// 找出相似组，返回成组的单品 id（每组 ≥ 2 件）。
    ///
    /// 分组规则与阈值在共享核心 `SimilarityGrouping` 中，这里只负责计算特征指纹与特征距离。
    /// - Parameters:
    ///   - featureThreshold: 特征距离阈值（越小越严格）。VNFeaturePrint 距离无固定上界，需用真实衣橱微调。
    ///   - colorThreshold: 主色 RGB 曼哈顿距离阈值（0...3，越小越严格）。
    func findSimilarGroups(
        _ inputs: [ItemFingerprintInput],
        featureThreshold: Float = SimilarityGrouping.featureThreshold,
        colorThreshold: Double = SimilarityGrouping.colorThreshold
    ) async -> [[UUID]] {
        // 1. 逐件计算特征指纹与主色。
        var prints: [UUID: VNFeaturePrintObservation] = [:]
        var colors: [UUID: StoredColor] = [:]
        for input in inputs {
            colors[input.id] = input.color
            if let data = input.imageData, let print = Self.featurePrint(from: data) {
                prints[input.id] = print
            }
        }

        // 2. 两两比较并聚组（O(n²)，手动工具可接受）。
        return SimilarityGrouping.groups(
            ids: inputs.map(\.id),
            colors: colors,
            featureThreshold: featureThreshold,
            colorThreshold: colorThreshold
        ) { a, b in
            guard let fa = prints[a], let fb = prints[b] else { return nil }
            var distance: Float = 0
            do {
                try fa.computeDistance(&distance, to: fb)
            } catch {
                return nil
            }
            return distance
        }
    }

    // MARK: - 工具

    /// 计算单张图的特征指纹。
    private static func featurePrint(from data: Data) -> VNFeaturePrintObservation? {
        guard let cgImage = makeCGImage(from: data) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
