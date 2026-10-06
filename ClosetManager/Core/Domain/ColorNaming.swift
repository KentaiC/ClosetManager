import Foundation

/// 精细颜色命名：把提取的主色映射到最接近的「具名颜色」（如「藏青」「酒红」）。
///
/// 比 `ColorCategory`（粗粒度色桶，用于看板聚合）更细，用于卡片/编辑页展示。
/// 做法：维护一张「具名参考色」表，取与目标色 RGB 距离最近者。
enum ColorNaming {
    /// (中文名, 参考 RGB 0...255)
    private static let table: [(name: String, r: Double, g: Double, b: Double)] = [
        ("黑色", 20, 20, 22),
        ("白色", 245, 245, 245),
        ("浅灰", 200, 200, 202),
        ("灰色", 130, 130, 134),
        ("深灰", 70, 72, 78),
        ("米白", 238, 232, 218),
        ("米色", 222, 208, 178),
        ("卡其", 195, 176, 145),
        ("驼色", 181, 145, 102),
        ("棕色", 120, 80, 50),
        ("咖啡", 78, 54, 41),
        ("酒红", 110, 30, 45),
        ("正红", 200, 40, 45),
        ("砖红", 170, 70, 55),
        ("粉色", 235, 170, 190),
        ("桃粉", 240, 150, 140),
        ("橙色", 232, 130, 50),
        ("姜黄", 205, 150, 40),
        ("黄色", 235, 205, 70),
        ("米黄", 230, 222, 160),
        ("草绿", 110, 180, 80),
        ("墨绿", 35, 80, 60),
        ("橄榄绿", 110, 120, 60),
        ("军绿", 90, 100, 70),
        ("青色", 70, 175, 170),
        ("天蓝", 120, 180, 225),
        ("蓝色", 50, 100, 200),
        ("海军蓝", 40, 70, 130),
        ("藏青", 30, 40, 80),
        ("紫色", 130, 80, 175),
        ("深紫", 80, 50, 110)
    ]

    /// 取与给定颜色最接近的具名颜色。
    static func name(for color: StoredColor) -> String {
        let r = color.red * 255, g = color.green * 255, b = color.blue * 255
        var best = table[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in table {
            let d = (entry.r - r) * (entry.r - r)
                  + (entry.g - g) * (entry.g - g)
                  + (entry.b - b) * (entry.b - b)
            if d < bestDistance {
                bestDistance = d
                best = entry
            }
        }
        return best.name
    }
}

extension StoredColor {
    /// 精细中文色名（如「藏青」「酒红」）。
    var refinedColorName: String { ColorNaming.name(for: self) }
}
