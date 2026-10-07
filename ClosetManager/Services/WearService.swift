import Foundation
import SwiftData

/// 穿搭生命周期与洗衣袋流转的业务逻辑（与 UI 解耦）。
///
/// 所有改动都直接作用于传入的 `ModelContext`，SwiftData 会驱动 `@Query` 自动刷新 UI。
enum WearService {

    // MARK: - 收藏

    /// 将一套草稿保存为收藏 `Outfit`。
    @discardableResult
    static func addToFavorites(
        _ draft: OutfitDraft,
        scenario: Scenario?,
        warmth: WarmthLevel?,
        in context: ModelContext
    ) -> Outfit {
        let outfit = Outfit(
            name: "收藏穿搭",
            isFavorite: true,
            source: .generated,
            targetScenario: scenario,
            targetWarmthLevel: warmth,
            items: draft.allItems
        )
        context.insert(outfit)
        return outfit
    }

    // MARK: - 今天穿这套 / 正在穿

    /// 将一套草稿设为「今天穿这套」（当前活动穿搭）。
    /// 会先把其它活动记录置为非活动，保证同一时刻至多一套在穿。
    @discardableResult
    static func wearToday(
        _ draft: OutfitDraft,
        outfit: Outfit? = nil,
        in context: ModelContext
    ) -> WearRecord {
        deactivateActiveRecords(in: context)
        let record = WearRecord(
            date: .now,
            isActive: true,
            outfit: outfit,
            items: draft.allItems
        )
        context.insert(record)
        return record
    }

    /// 穿收藏前的检查：每件单品都在衣橱中，且上装、下装、鞋子齐全（审计 H-03）。
    /// 返回给用户的提示；可以穿时返回 nil。规则在共享核心 `ItemLifecycle.checkWear` 中。
    static func wearProblem(for outfit: Outfit) -> String? {
        ItemLifecycle.checkWear(
            outfit.items.map {
                ItemLifecycle.WearCandidate(
                    title: ItemDefaults.displayTitle(name: $0.name, category: $0.category), category: $0.category, status: $0.status)
            },
            requireComplete: true
        ).message
    }

    /// 将一套已收藏的 `Outfit` 设为「今天穿这套」。调用前先用 `wearProblem(for:)` 检查。
    @discardableResult
    static func wearOutfit(_ outfit: Outfit, in context: ModelContext) -> WearRecord {
        deactivateActiveRecords(in: context)
        let record = WearRecord(
            date: .now,
            isActive: true,
            outfit: outfit,
            items: outfit.items
        )
        context.insert(record)
        return record
    }

    /// 取消所有「正在穿」标记（不改变单品状态，仅转为历史）。
    static func deactivateActiveRecords(in context: ModelContext) {
        let descriptor = FetchDescriptor<WearRecord>(
            predicate: #Predicate { $0.isActive }
        )
        guard let actives = try? context.fetch(descriptor) else { return }
        for record in actives {
            record.isActive = false
        }
    }

    // MARK: - 脱下流转

    /// 脱下当前穿搭并流转：勾选的单品进洗衣袋，未勾选的留在衣橱。
    /// 只处理当前在衣橱中的单品，在洗衣袋或行李箱中的单品保持不变（审计 H-03），规则在共享核心 `ItemLifecycle.takeOff` 中。
    /// 记录本身保留为当天的日历历史（`isActive` 置为 false）。
    static func takeOff(
        _ record: WearRecord,
        laundryItems: Set<ClothingItem>,
        in context: ModelContext
    ) {
        let now = Date.now
        for item in record.items where item.status == .inWardrobe {
            let next = ItemLifecycle.takeOff(
                ItemLifecycle.State(status: item.status, laundryEntryDate: item.laundryEntryDate),
                sentToLaundry: laundryItems.contains(item),
                now: now   // 进洗衣袋时记录入袋时间，用于滞留预警
            )
            item.status = next.status
            item.laundryEntryDate = next.laundryEntryDate
            item.updatedAt = now
        }
        record.isActive = false
    }

    // MARK: - 洗衣房

    /// 将一批单品「洗净放回」衣橱。
    static func returnToWardrobe(_ items: some Sequence<ClothingItem>, in context: ModelContext) {
        for item in items {
            item.status = .inWardrobe
            item.laundryEntryDate = nil
            item.updatedAt = .now
        }
    }

    // MARK: - 差旅打包

    /// 将一批单品装入行李箱（差旅期间隔离出日常衣橱）。
    static func packIntoLuggage(_ items: some Sequence<ClothingItem>, in context: ModelContext) {
        for item in items {
            item.status = .inLuggage
            item.updatedAt = .now
        }
    }

    /// 结束差旅：把行李箱里的单品全部取出回到衣橱。
    static func unpackAllLuggage(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClothingItem>()
        guard let all = try? context.fetch(descriptor) else { return }
        for item in all where item.status == .inLuggage {
            item.status = .inWardrobe
            item.updatedAt = .now
        }
    }
}
