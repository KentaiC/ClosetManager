import Foundation

/// 衣物顶层分类（互斥，单选）。
///
/// 严格约束：
/// - 六大分类互斥，一件单品只能属于其中之一。
/// - 「配饰 (accessory)」「袜子 (socks)」均为独立分类，绝不可与「上装 (top)」混淆。
/// - 每个顶层分类下还有二级子类，见 `Subtype` 与 `subtypes`。
enum Category: String, Codable, CaseIterable, Identifiable {
    case outerwear   // 外套
    case top         // 上装
    case bottom      // 下装
    case shoes       // 鞋子
    case accessory   // 配饰
    case socks       // 袜子

    var id: String { rawValue }

    /// 中文名称（用于 UI 展示）。
    var displayName: String {
        switch self {
        case .outerwear: return "外套"
        case .top:       return "上装"
        case .bottom:    return "下装"
        case .shoes:     return "鞋子"
        case .accessory: return "配饰"
        case .socks:     return "袜子"
        }
    }

    /// SF Symbols 图标名（占位，UI 阶段再统一校准可用性）。
    var symbolName: String {
        switch self {
        case .outerwear: return "jacket"
        case .top:       return "tshirt"
        case .bottom:    return "rectangle.portrait"
        case .shoes:     return "shoeprints.fill"
        case .accessory: return "bag"
        case .socks:     return "circle.bottomhalf.filled"
        }
    }

    /// 在一套 Outfit 中是否为必选槽位（上装 / 下装 / 鞋子必选）。
    var isRequiredInOutfit: Bool {
        switch self {
        case .top, .bottom, .shoes: return true
        case .outerwear, .accessory, .socks: return false
        }
    }

    /// 「脱下」时，该分类是否默认勾选进洗衣袋（智能默认值，用户仍可手动改）。
    ///
    /// 生活常识：上装 / 下装 / 袜子贴身，默认要洗；外套 / 鞋子 / 配饰默认不洗。
    var washByDefaultOnTakeOff: Bool {
        switch self {
        case .top, .bottom, .socks: return true
        case .outerwear, .shoes, .accessory: return false
        }
    }

    /// 该分类下的全部二级子类。
    var subtypes: [Subtype] {
        Subtype.allCases.filter { $0.category == self }
    }
}
