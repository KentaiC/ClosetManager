import Foundation

/// 高级筛选条件（与 App 的高级筛选页面相同）。
public struct WardrobeSearch: Sendable, Equatable {
    public var scenario: Scenario?
    public var waterproofOnly: Bool
    public var colorCategory: ColorCategory?
    /// 只保留在 `unwornSince` 之后没有穿着记录的单品。
    public var unwornSince: Date?

    public init(scenario: Scenario? = nil, waterproofOnly: Bool = false, colorCategory: ColorCategory? = nil, unwornSince: Date? = nil) {
        self.scenario = scenario
        self.waterproofOnly = waterproofOnly
        self.colorCategory = colorCategory
        self.unwornSince = unwornSince
    }

    /// 「过去 N 天未穿」的截止时间。
    public static func unwornCutoff(days: Int = WardrobeRules.unwornDays, now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// - Parameter lastWornDate: 该单品最近一次出现在穿着记录中的日期，没有记录时为 nil。
    public func matches<Item: WardrobeItemRepresentable>(_ item: Item, lastWornDate: Date?) -> Bool {
        if let scenario, !item.scenarios.contains(scenario) { return false }
        if waterproofOnly, !item.isWaterproof { return false }
        if let colorCategory, item.dominantColorCategory != colorCategory { return false }
        if let unwornSince, let lastWornDate, lastWornDate >= unwornSince { return false }
        return true
    }
}
