import Foundation

/// 主辅色提取规则（从 App 的 `VisionService.extractColors` 移入共享核心）。
///
/// 输入是缩放到 `sampleSize × sampleSize` 的 RGBA8 像素。图片解码与缩放属于平台框架的工作，
/// 由调用方完成；这里只做纯计算，App 与本地 Web 服务端得到相同结果。
public enum ColorExtraction {
    /// 取色前把图片缩放到的边长。
    public static let sampleSize = 48

    /// 无法取色时使用的中性灰。
    public static let fallback = StoredColor(red: 0.5, green: 0.5, blue: 0.5)

    /// 每个通道的量化级数，颜色桶共 6×6×6 个。
    static let levels = 6

    /// alpha 低于此值的像素视为透明背景，不参与统计。
    static let minimumAlpha: UInt8 = 32

    /// 辅色与主色的 RGB 曼哈顿距离至少要超过此值。
    static let secondaryDistance = 0.25

    /// 从 RGBA8 像素中提取主色（占比最高的颜色桶的平均色）与辅色（第一个与主色差异足够大的桶）。
    ///
    /// 建议传入已抠图的数据，透明背景会被跳过，只统计衣物本体。没有不透明像素时返回中性灰、无辅色。
    /// 件数相同的桶按桶编号排序。App 原实现在这种情况下的顺序取决于字典遍历顺序，结果不固定；
    /// 这里固定下来，结果仍是原实现可能给出的结果之一。
    public static func extract(rgba pixels: [UInt8]) -> (dominant: StoredColor, secondary: StoredColor?) {
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var index = 0
        while index + 3 < pixels.count {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2], a = pixels[index + 3]
            index += 4
            if a < minimumAlpha { continue }
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
        let sorted = buckets.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map(\.value)

        func averageColor(_ e: (count: Int, r: Double, g: Double, b: Double)) -> StoredColor {
            StoredColor(
                red: e.r / Double(e.count) / 255,
                green: e.g / Double(e.count) / 255,
                blue: e.b / Double(e.count) / 255
            )
        }

        let dominant = averageColor(sorted[0])
        var secondary: StoredColor?
        for entry in sorted.dropFirst() {
            let c = averageColor(entry)
            if SimilarityGrouping.colorDistance(c, dominant) > secondaryDistance { secondary = c; break }
        }
        return (dominant, secondary)
    }
}
