import Foundation
import SwiftData

/// 一套穿搭。
///
/// 结构约束（由 `missingRequiredSlots` / `isStructurallyValid` 校验）：
/// [外套(可选)] + [上装(必选)] + [下装(必选)] + [鞋子(必选)] + [配饰(可选)]
///
/// 设计说明：组成单品采用单一 `items` 多对多关系，槽位（外套/上装/...）通过按
/// `Category` 过滤的计算属性派生。相比为每个槽位声明独立的同类型关系，单一关系在
/// SwiftData 中更稳健（避免同类型多关系的反向推断歧义），也天然支持「一件单品被多套穿搭复用」。
@Model
final class Outfit {
    @Attribute(.unique) var id: UUID
    var name: String

    /// 是否收藏（一键保存到 Favorites）。
    var isFavorite: Bool

    /// 来源：算法生成 / 手动拼搭。
    var source: OutfitSource

    /// 生成时的目标场景（用于回溯，可空）。
    var targetScenario: Scenario?

    /// 生成时的目标保暖标签 / 当前天气（用于回溯，可空）。
    var targetWarmthLevel: WarmthLevel?

    /// 自由画布的布局信息（各单品的位置 / 缩放 / 层级），手动拼搭时序列化存储。
    @Attribute(.externalStorage) var canvasLayoutData: Data?

    var createdAt: Date
    var updatedAt: Date

    // MARK: - 关系

    /// 组成该穿搭的单品集合（多对多）。在此侧声明反向关系到 `ClothingItem.outfits`。
    /// 删除单品时仅置空关联（nullify），不连带删除穿搭。
    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.outfits)
    var items: [ClothingItem]

    /// 该穿搭关联的日历记录。在此侧声明反向关系到 `WearRecord.outfit`。
    @Relationship(deleteRule: .nullify, inverse: \WearRecord.outfit)
    var wearRecords: [WearRecord]

    init(
        id: UUID = UUID(),
        name: String = "未命名穿搭",
        isFavorite: Bool = false,
        source: OutfitSource = .generated,
        targetScenario: Scenario? = nil,
        targetWarmthLevel: WarmthLevel? = nil,
        items: [ClothingItem] = [],
        canvasLayoutData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.source = source
        self.targetScenario = targetScenario
        self.targetWarmthLevel = targetWarmthLevel
        self.items = items
        self.canvasLayoutData = canvasLayoutData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.wearRecords = []
    }
}

// MARK: - 槽位派生与结构校验

extension Outfit {
    /// 外套（可选）。取第一件外套。
    var outerwear: ClothingItem? { items.first { $0.category == .outerwear } }

    /// 上装（必选）。
    var top: ClothingItem? { items.first { $0.category == .top } }

    /// 下装（必选）。
    var bottom: ClothingItem? { items.first { $0.category == .bottom } }

    /// 鞋子（必选）。
    var shoes: ClothingItem? { items.first { $0.category == .shoes } }

    /// 配饰（可选，可多件）。
    var accessories: [ClothingItem] { items.filter { $0.category == .accessory } }

    /// 袜子（可选）。
    var socks: ClothingItem? { items.first { $0.category == .socks } }

    /// 缺失的必选槽位（上装 / 下装 / 鞋子）。
    var missingRequiredSlots: [Category] {
        Category.allCases.filter { category in
            category.isRequiredInOutfit && !items.contains { $0.category == category }
        }
    }

    /// 是否满足结构约束（必选槽位齐全）。
    var isStructurallyValid: Bool { missingRequiredSlots.isEmpty }
}
