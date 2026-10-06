import XCTest
import ClosetCore

final class AnalyticsServiceTests: XCTestCase {
    func testInventoryFollowsCategoryOrderAndOmitsEmpty() {
        let items = [TestItem(.jeans), TestItem(.tee), TestItem(.shirt), TestItem(.hat)]
        let rows = AnalyticsService.inventoryByCategory(items)
        XCTAssertEqual(rows.map(\.category), [.top, .bottom, .accessory])
        XCTAssertEqual(rows.map(\.count), [2, 1, 1])
    }

    func testColorInventoryCountsAndSortsDescending() {
        let items = [TestItem(.tee, color: .blue), TestItem(.jeans, color: .blue), TestItem(.hat, color: .red)]
        let rows = AnalyticsService.colorInventory(items)
        XCTAssertEqual(rows.first?.color, .blue)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.color, $0.count) }), [.blue: 2, .red: 1])
    }

    func testColorFrequencyCountsEveryWornItem() {
        let blue = TestItem(.tee, color: .blue), red = TestItem(.jeans, color: .red)
        let records = [TestRecord(date: .now, items: [blue, red]), TestRecord(date: .now, items: [blue])]
        let rows = AnalyticsService.colorFrequency(records)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.color, $0.count) }), [.blue: 2, .red: 1])
        XCTAssertEqual(rows.first?.color, .blue)
    }

    func testDailyActivityGroupsByStartOfDayInGivenCalendar() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSince1970: 1_780_000_000)           // 2026-05-28 20:26:40 UTC
        let sameDay = morning.addingTimeInterval(3_000)
        let nextDay = morning.addingTimeInterval(86_400)
        let records = [morning, sameDay, nextDay].map { TestRecord(date: $0, items: []) }
        let activity = AnalyticsService.dailyActivity(records, calendar: utc)
        XCTAssertEqual(activity[utc.startOfDay(for: morning)], 2)
        XCTAssertEqual(activity[utc.startOfDay(for: nextDay)], 1)
        XCTAssertEqual(activity.count, 2)
    }
}
