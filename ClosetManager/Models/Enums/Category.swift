import Foundation

/// 衣物分类（互斥，单选）。
///
/// 严格约束：
/// - 五大分类互斥，一件单品只能属于其中之一。
/// - 「配饰 (accessory)」是独立分类，绝不可与「上装 (top)」混淆。
enum Category: String, Codable, CaseIterable, Identifiable {
    case outerwear   // 外套
    case top         // 上装
    case bottom      // 下装
    case shoes       // 鞋子
    case accessory   // 配饰

    var id: String { rawValue }

    /// 中文名称（用于 UI 展示）。
    var displayName: String {
        switch self {
        case .outerwear: return "外套"
        case .top:       return "上装"
        case .bottom:    return "下装"
        case .shoes:     return "鞋子"
        case .accessory: return "配饰"
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
        }
    }

    /// 在一套 Outfit 中是否为必选槽位（上装 / 下装 / 鞋子必选）。
    var isRequiredInOutfit: Bool {
        switch self {
        case .top, .bottom, .shoes: return true
        case .outerwear, .accessory: return false
        }
    }
}
