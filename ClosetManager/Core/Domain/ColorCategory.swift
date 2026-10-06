import Foundation

/// 颜色归类（用于数据看板的「颜色占比」统计）。
///
/// CoreImage 提取出的主色是连续的 RGB 值，无法直接做占比聚合；
/// 因此将精确主色映射到有限的颜色桶，落库到 `ClothingItem.dominantColorCategory`，
/// 看板侧即可直接按枚举分组统计。
enum ColorCategory: String, Codable, CaseIterable, Identifiable {
    case black, white, gray, beige, brown
    case red, orange, yellow, green, cyan, blue, purple, pink
    case multicolor   // 多色 / 难以归类

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black:      return "黑色"
        case .white:      return "白色"
        case .gray:       return "灰色"
        case .beige:      return "米色"
        case .brown:      return "棕色"
        case .red:        return "红色"
        case .orange:     return "橙色"
        case .yellow:     return "黄色"
        case .green:      return "绿色"
        case .cyan:       return "青色"
        case .blue:       return "蓝色"
        case .purple:     return "紫色"
        case .pink:       return "粉色"
        case .multicolor: return "多色"
        }
    }
}

extension ColorCategory {
    /// 依据 HSB 将存储颜色归类到颜色桶。
    ///
    /// 归类策略：
    /// 1. 低饱和度视为无彩色系，按明度区分 黑 / 灰 / 白；
    /// 2. 暖色相区间内，低明度归为棕色、低饱和归为米色；
    /// 3. 其余按色相落入对应彩色桶。
    static func classify(_ color: StoredColor) -> ColorCategory {
        let (hue, saturation, brightness) = color.hsb

        // 1. 无彩色系
        if saturation < 0.12 {
            switch brightness {
            case ..<0.22: return .black
            case 0.9...:  return .white
            default:      return .gray
            }
        }

        // 2. 暖色低饱和 / 低明度 → 米色 / 棕色
        if hue >= 20 && hue < 50 {
            if brightness < 0.5 { return .brown }
            if saturation < 0.4 { return .beige }
        }

        // 3. 有彩色系，按色相归类
        switch hue {
        case 0..<15, 345...360: return .red
        case 15..<45:           return .orange
        case 45..<70:           return .yellow
        case 70..<170:          return .green
        case 170..<200:         return .cyan
        case 200..<255:         return .blue
        case 255..<290:         return .purple
        default:                return .pink
        }
    }
}
