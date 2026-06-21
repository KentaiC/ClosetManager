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

    /// 将一套已收藏的 `Outfit` 设为「今天穿这套」。
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

    /// 脱下当前穿搭并流转：勾选的单品进洗衣袋，未勾选的回到衣橱。
    /// 记录本身保留为当天的日历历史（`isActive` 置为 false）。
    static func takeOff(
        _ record: WearRecord,
        laundryItems: Set<ClothingItem>,
        in context: ModelContext
    ) {
        for item in record.items {
            if laundryItems.contains(item) {
                item.status = .inLaundry
                item.laundryEntryDate = .now   // 记录入袋时间，用于滞留预警
            } else {
                item.status = .inWardrobe
                item.laundryEntryDate = nil
            }
            item.updatedAt = .now
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
