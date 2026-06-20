import Foundation

/// 保暖程度标签（替代具体温度数值，降低录入复杂度）。
///
/// 顺序即由「冷」到「热」，`allCases` 可直接用于有序展示。
/// 适用季节由该标签自动推导（见 `seasons`），用户可在此基础上手动覆盖。
enum WarmthLevel: String, Codable, CaseIterable, Identifiable {
    case frigid   // 严寒
    case cold     // 寒冷
    case cool     // 凉爽
    case mild     // 温和
    case warm     // 暖和
    case hot      // 炎热

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frigid: return "严寒"
        case .cold:   return "寒冷"
        case .cool:   return "凉爽"
        case .mild:   return "温和"
        case .warm:   return "暖和"
        case .hot:    return "炎热"
        }
    }

    /// 代表性图标（温度计由冷到热）。
    var symbolName: String {
        switch self {
        case .frigid: return "thermometer.snowflake"
        case .cold:   return "thermometer.low"
        case .cool:   return "thermometer.low"
        case .mild:   return "thermometer.medium"
        case .warm:   return "thermometer.high"
        case .hot:    return "thermometer.sun.fill"
        }
    }

    /// 该保暖标签对应的季节（用于自动推导单品的适用季节）。
    var seasons: Set<Season> {
        switch self {
        case .frigid: return [.winter]
        case .cold:   return [.autumn, .winter]
        case .cool:   return [.spring, .autumn]
        case .mild:   return [.spring, .autumn]
        case .warm:   return [.spring, .summer]
        case .hot:    return [.summer]
        }
    }
}
