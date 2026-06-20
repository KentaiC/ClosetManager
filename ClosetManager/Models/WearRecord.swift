import Foundation
import SwiftData

/// 穿搭日历记录：记录「某一天穿了哪套 / 哪些单品」。
///
/// 与洗衣袋流转的关系：
/// - 用户把穿搭记录到日历后，「脱下」动作由上层逻辑决定每件单品的流转
///   （扔进洗衣袋 `inLaundry` 或返回衣橱 `inWardrobe`）；
/// - 本记录保留当天实际穿着的单品快照，用于日历回看与（后续）穿着频率分析。
@Model
final class WearRecord {
    @Attribute(.unique) var id: UUID

    /// 穿着日期（按天记录）。
    var date: Date

    /// 关联的穿搭（可空：也允许只记录零散单品，而非完整 Outfit）。
    /// 反向关系声明在 `Outfit.wearRecords`。
    var outfit: Outfit?

    /// 当天实际穿着的单品（多对多）。在此侧声明反向关系到 `ClothingItem.wearRecords`。
    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.wearRecords)
    var items: [ClothingItem]

    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        outfit: Outfit? = nil,
        items: [ClothingItem] = [],
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.outfit = outfit
        self.items = items
        self.notes = notes
        self.createdAt = createdAt
    }
}
