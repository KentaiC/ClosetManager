import Foundation

/// 单品状态机：在衣橱 / 在洗衣袋 / 在行李箱。
///
/// - `inWardrobe`：在衣橱，**仅此状态**参与穿搭生成算法。
/// - `inLaundry`：在洗衣袋（待清洗），由「脱下」流转写入，并记录 `laundryEntryDate`。
/// - `inLuggage`：在行李箱（差旅打包期间），与日常衣橱算法隔离。
public enum ItemStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inWardrobe
    case inLaundry
    case inLuggage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inWardrobe: return "在衣橱"
        case .inLaundry:  return "在洗衣袋"
        case .inLuggage:  return "在行李箱"
        }
    }
}
