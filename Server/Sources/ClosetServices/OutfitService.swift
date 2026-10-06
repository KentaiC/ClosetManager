import Foundation
import ClosetCore
import ClosetStorage

/// 带槽位的生成结果。
public struct SlottedDraft: Sendable {
    public var id: UUID
    public var members: [(slot: OutfitSlot, item: StoredItem)]
}

extension OutfitDraftOf where Item == StoredItem {
    /// 按 `allItems` 的顺序（由外到内、自上而下）列出成员及其槽位。
    var slottedMembers: [(slot: OutfitSlot, item: StoredItem)] {
        let pairs: [(OutfitSlot, StoredItem?)] = [
            (.outerwear, outerwear), (.midLayer, midLayer), (.top, top), (.bottom, bottom),
            (.socks, socks), (.shoes, shoes), (.accessory, accessory),
        ]
        return pairs.compactMap { slot, item in item.map { (slot, $0) } }
    }
}

/// 穿搭生成、收藏与删除。
public struct OutfitService: Sendable {
    let store: ClosetStore
    let now: @Sendable () -> Date

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// 智能生成，算法来自共享核心 `OutfitGenerationEngine`，候选为全部单品（引擎自行筛选在衣橱的单品）。
    public func suggestions<G: RandomNumberGenerator>(
        warmth: WarmthLevel, scenario: Scenario, requireWaterproof: Bool, maxCount: Int = 8, using rng: inout G
    ) async throws -> (drafts: [SlottedDraft], missingRequired: [ClosetCore.Category]) {
        let items = try await store.read { try $0.items() }
        let result = OutfitGenerationEngine.generate(
            from: items, warmth: warmth, scenario: scenario, requireWaterproof: requireWaterproof, maxCount: maxCount, using: &rng)
        return (result.drafts.map { SlottedDraft(id: $0.id, members: $0.slottedMembers) }, result.missingRequired)
    }

    /// 保存一套穿搭（`WearService.addToFavorites`）。名称为空时与 App 相同，使用「收藏穿搭」。
    ///
    /// 与 App 的差异：来源按调用方实际情况记录。App 把手动拼搭也记为「算法生成」（审计 M-05），
    /// 这与 `OutfitSource` 的定义矛盾，Web 版按定义记录。
    public func create(
        name: String?, isFavorite: Bool, source: OutfitSource, targetScenario: Scenario?, targetWarmthLevel: WarmthLevel?,
        members: [SlottedItemID]
    ) async throws -> StoredOutfit {
        guard !members.isEmpty else { throw ServiceError.invalid("穿搭中没有单品。") }
        let timestamp = now()
        let outfit = StoredOutfit(
            id: UUID(), name: (name?.isEmpty ?? true) ? "收藏穿搭" : name!, isFavorite: isFavorite, source: source,
            targetScenario: targetScenario, targetWarmthLevel: targetWarmthLevel, members: members,
            createdAt: timestamp, updatedAt: timestamp)
        return try await store.transaction { session in
            try LifecycleService.requireItems(session, members.map(\.itemID))
            try session.insertOutfit(outfit)
            return outfit
        }
    }

    public func delete(id: UUID) async throws {
        let deleted = try await store.transaction { try $0.deleteOutfit(id: id) }
        guard deleted else { throw ServiceError.notFound("未找到该穿搭。") }
    }
}
