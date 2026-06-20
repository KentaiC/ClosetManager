import Foundation

/// 单品状态机：在衣橱 / 在洗衣袋。
///
/// 状态流转由「洗衣袋流转系统」驱动：
/// - 穿搭记录到日历后选择「脱下」时，单品可被扔进洗衣袋 (`inLaundry`)；
/// - 也可直接返回衣橱候选池 (`inWardrobe`)。
/// - 仅 `inWardrobe` 的单品参与穿搭生成算法。
enum ItemStatus: String, Codable, CaseIterable, Identifiable {
    case inWardrobe  // 在衣橱（可用于穿搭）
    case inLaundry   // 在洗衣袋（待清洗，暂不可用）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inWardrobe: return "在衣橱"
        case .inLaundry:  return "在洗衣袋"
        }
    }
}
