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
    /// - Parameters:
    ///   - featureThreshold: 特征距离阈值（越小越严格）。VNFeaturePrint 距离无固定上界，需用真实衣橱微调。
    ///   - colorThreshold: 主色 RGB 曼哈顿距离阈值（0...3，越小越严格）。
    func findSimilarGroups(
        _ inputs: [ItemFingerprintInput],
        featureThreshold: Float = 0.6,
        colorThreshold: Double = 0.30
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

        // 2. 并查集初始化。
        var parent: [UUID: UUID] = [:]
        for input in inputs { parent[input.id] = input.id }
        func find(_ x: UUID) -> UUID {
            var root = x
            while parent[root] != root { root = parent[root]! }
            return root
        }
        func union(_ a: UUID, _ b: UUID) { parent[find(a)] = find(b) }

        // 3. 两两比较（O(n²)，手动工具可接受）。
        let ids = inputs.map(\.id)
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let a = ids[i], b = ids[j]
                guard let fa = prints[a], let fb = prints[b],
                      let ca = colors[a], let cb = colors[b] else { continue }
                var distance: Float = 0
                do {
                    try fa.computeDistance(&distance, to: fb)
                } catch {
                    continue
                }
                if distance < featureThreshold && Self.colorDistance(ca, cb) < colorThreshold {
                    union(a, b)
                }
            }
        }

        // 4. 按根聚组，保留 ≥ 2 件的组。
        var groups: [UUID: [UUID]] = [:]
        for id in ids {
            groups[find(id), default: []].append(id)
        }
        return groups.values.filter { $0.count >= 2 }.map { $0 }
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

    /// 主色 RGB 曼哈顿距离。
    private static func colorDistance(_ a: StoredColor, _ b: StoredColor) -> Double {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
    }
}
