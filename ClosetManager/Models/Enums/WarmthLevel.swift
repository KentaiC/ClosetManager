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

// MARK: - 保暖度（1~100）与档位互转、叠穿预算

extension WarmthLevel {
    /// 由单品保暖度（1~100）映射到 6 档（用于季节推导与展示）。
    static func from(score: Int) -> WarmthLevel {
        switch score {
        case ..<17:  return .hot
        case 17..<34: return .warm
        case 34..<51: return .mild
        case 51..<68: return .cool
        case 68..<85: return .cold
        default:      return .frigid
        }
    }

    /// 该档位的代表保暖度（滑条默认值用）。
    var representativeScore: Int {
        switch self {
        case .hot: return 12
        case .warm: return 25
        case .mild: return 42
        case .cool: return 59
        case .cold: return 76
        case .frigid: return 92
        }
    }

    /// 当前环境（当天天气）期望的「躯干层保暖度总和」目标。
    /// 数值越冷越高，叠穿算法据此堆叠层数。
    var torsoBudget: Int {
        switch self {
        case .hot: return 22
        case .warm: return 40
        case .mild: return 62
        case .cool: return 88
        case .cold: return 130
        case .frigid: return 170
        }
    }

    /// 「气温向下兼容」：当前环境允许的单件最大保暖度。
    /// 炎热天禁止出现高保暖单品（如羽绒），但低保暖单品可在严寒作为最内层打底。
    var maxSingleGarmentWarmth: Int {
        switch self {
        case .hot: return 38
        case .warm: return 58
        case .mild: return 78
        case .cool: return 100
        case .cold: return 100
        case .frigid: return 100
        }
    }
}
