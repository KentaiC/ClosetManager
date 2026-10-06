import Foundation
import ClosetCore
import ClosetStorage

/// 看板统计结果。
public struct AnalyticsSummary: Sendable {
    public var inventory: [(category: ClosetCore.Category, count: Int)]
    public var colorInventory: [(color: ColorCategory, count: Int)]
    public var colorFrequency: [(color: ColorCategory, count: Int)]
    public var dailyActivity: [Date: Int]
}

/// 穿着记录在统计中的只读视图。
struct RecordForAnalytics: WearRecordRepresentable {
    var date: Date
    var items: [StoredItem]
}

/// 差旅打包计划。
public struct TravelPlan: Sendable {
    public var days: Int
    public var underwearCount: Int
    public var socksCount: Int
    public var showsCapHint: Bool
    public var suggestion: [StoredItem]
    public var missingRequired: [ClosetCore.Category]
}

/// 看板、高级筛选、差旅计划：全部是对共享核心规则的只读调用。
public struct InsightService: Sendable {
    let store: ClosetStore
    let now: @Sendable () -> Date
    let calendar: Calendar

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    /// 看板统计（`AnalyticsDashboardView` 使用的四项）。
    public func analytics() async throws -> AnalyticsSummary {
        let (items, records) = try await store.read { session -> ([StoredItem], [ResolvedWearRecord]) in
            let items = try session.items()
            let records = try session.wearRecords()
            let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            return (items, records.map { ResolvedWearRecord(record: $0, items: $0.itemIDs.compactMap { map[$0] }) })
        }
        let forAnalytics = records.map { RecordForAnalytics(date: $0.record.date, items: $0.items) }
        return AnalyticsSummary(
            inventory: AnalyticsService.inventoryByCategory(items),
            colorInventory: AnalyticsService.colorInventory(items),
            colorFrequency: AnalyticsService.colorFrequency(forAnalytics),
            dailyActivity: AnalyticsService.dailyActivity(forAnalytics, calendar: calendar))
    }

    /// 高级筛选（`WardrobeSearchView`）。`unwornDays` 为 nil 时不按穿着时间筛选。
    public func search(scenario: Scenario?, waterproofOnly: Bool, colorCategory: ColorCategory?, unwornDays: Int?) async throws -> [StoredItem] {
        let cutoff = unwornDays.map { WardrobeSearch.unwornCutoff(days: $0, now: now(), calendar: calendar) }
        let criteria = WardrobeSearch(scenario: scenario, waterproofOnly: waterproofOnly, colorCategory: colorCategory, unwornSince: cutoff)
        let (items, lastWorn) = try await store.read { (try $0.items(), try $0.lastWornDates()) }
        return items.filter { criteria.matches($0, lastWornDate: lastWorn[$0.id]) }
    }

    /// 差旅打包计划（`TravelCapsuleView`）：基础携带数量与按行程生成的打包建议。
    public func travelPlan<G: RandomNumberGenerator>(days: Int, warmth: WarmthLevel, scenario: Scenario, using rng: inout G) async throws -> TravelPlan {
        guard (1...30).contains(days) else { throw ServiceError.invalid("旅行天数必须在 1 到 30 之间。") }
        let items = try await store.read { try $0.items() }
        let result = OutfitGenerationEngine.generate(from: items, warmth: warmth, scenario: scenario, maxCount: days, using: &rng)
        return TravelPlan(
            days: days,
            underwearCount: TravelService.underwearCount(days: days),
            socksCount: TravelService.socksCount(days: days),
            showsCapHint: TravelService.showsCapHint(days: days),
            suggestion: TravelService.packingSuggestion(from: result),
            missingRequired: result.missingRequired)
    }
}
