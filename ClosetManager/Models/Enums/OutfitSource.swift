import Foundation

/// 穿搭来源：算法生成 / 手动画布拼搭。
///
/// 用于区分一套 Outfit 是由本地穿搭引擎生成，还是用户在自由画布手动拼搭后收藏。
enum OutfitSource: String, Codable, CaseIterable, Identifiable {
    case generated   // 算法生成
    case manual      // 自由画布手动拼搭

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .generated: return "智能生成"
        case .manual:    return "手动拼搭"
        }
    }
}
