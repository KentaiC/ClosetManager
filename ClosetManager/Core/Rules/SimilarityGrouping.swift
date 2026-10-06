import Foundation

/// 相似单品分组规则（从 App 的 `DuplicationDetectorService` 移入共享核心）。
///
/// 两件单品的图像特征距离与主色距离同时低于阈值时视为相似，相似关系可以传递，
/// 用并查集聚成组。图像特征距离由平台框架计算，这里通过闭包传入。
public enum SimilarityGrouping {
    /// 图像特征距离阈值，越小越严格。特征距离没有固定上界，需要用真实衣橱微调。
    public static let featureThreshold: Float = 0.6

    /// 主色 RGB 曼哈顿距离阈值（0...3），越小越严格。
    public static let colorThreshold = 0.30

    /// 主色 RGB 曼哈顿距离。
    public static func colorDistance(_ a: StoredColor, _ b: StoredColor) -> Double {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
    }

    /// 找出相似组，每组至少两件。
    ///
    /// 与 App 相同，所有单品两两比较，不区分分类（审计 M-10，保持现状）。
    /// 组内按 `ids` 的顺序排列，组之间按各组第一件在 `ids` 中的位置排列。
    /// - Parameter featureDistance: 两件单品的图像特征距离；任意一件没有特征或比较失败时返回 nil，视为不相似。
    public static func groups(
        ids: [UUID],
        colors: [UUID: StoredColor],
        featureThreshold: Float = featureThreshold,
        colorThreshold: Double = colorThreshold,
        featureDistance: (UUID, UUID) -> Float?
    ) -> [[UUID]] {
        var parent: [UUID: UUID] = [:]
        for id in ids { parent[id] = id }
        func find(_ x: UUID) -> UUID {
            var root = x
            while let next = parent[root], next != root { root = next }
            return root
        }
        func union(_ a: UUID, _ b: UUID) { parent[find(a)] = find(b) }

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let a = ids[i], b = ids[j]
                guard let ca = colors[a], let cb = colors[b], let distance = featureDistance(a, b) else { continue }
                if distance < featureThreshold && colorDistance(ca, cb) < colorThreshold {
                    union(a, b)
                }
            }
        }

        var grouped: [UUID: [UUID]] = [:]
        var rootsInOrder: [UUID] = []
        for id in ids {
            let root = find(id)
            if grouped[root] == nil { rootsInOrder.append(root) }
            grouped[root, default: []].append(id)
        }
        return rootsInOrder.compactMap { grouped[$0] }.filter { $0.count >= 2 }
    }
}
