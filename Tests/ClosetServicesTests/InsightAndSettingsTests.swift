import XCTest
import ClosetCore
import ClosetStorage
@testable import ClosetServices

final class InsightServiceTests: XCTestCase {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testAnalyticsAndSearch() async throws {
        let store = try makeStore()
        let blueTee = storedItem(.tee, scenarios: [.work], waterproof: true)
        let redJeans = storedItem(.jeans, scenarios: [.casual], color: StoredColor(red: 0.8, green: 0.1, blue: 0.1))
        let oldCoat = storedItem(.overcoat, scenarios: [.work])
        try await insert(store, [blueTee, redJeans, oldCoat])
        let recent = fixedNow.addingTimeInterval(-10 * 86_400), old = fixedNow.addingTimeInterval(-200 * 86_400)
        try await store.transaction { s in
            try s.insertWearRecord(StoredWearRecord(id: UUID(), date: recent, isActive: false, outfitID: nil,
                                                    members: [SlottedItemID(itemID: blueTee.id), SlottedItemID(itemID: redJeans.id)], notes: nil, createdAt: recent))
            try s.insertWearRecord(StoredWearRecord(id: UUID(), date: old, isActive: false, outfitID: nil,
                                                    members: [SlottedItemID(itemID: oldCoat.id)], notes: nil, createdAt: old))
        }
        let service = InsightService(store: store, now: { fixedNow }, calendar: utc)

        let summary = try await service.analytics()
        XCTAssertEqual(summary.inventory.map(\.category), [.outerwear, .top, .bottom])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: summary.colorFrequency.map { ($0.color, $0.count) }), [.blue: 2, .red: 1])
        XCTAssertEqual(summary.dailyActivity.values.sorted(), [1, 1])

        let unworn = try await service.search(scenario: nil, waterproofOnly: false, colorCategory: nil, unwornDays: 90)
        XCTAssertEqual(unworn.map(\.id), [oldCoat.id])
        let work = try await service.search(scenario: .work, waterproofOnly: true, colorCategory: .blue, unwornDays: nil)
        XCTAssertEqual(work.map(\.id), [blueTee.id])
    }

    func testTravelPlan() async throws {
        let store = try makeStore()
        try await insert(store, [storedItem(.tee), storedItem(.shirt), storedItem(.jeans), storedItem(.sneakers)])
        let service = InsightService(store: store, now: { fixedNow }, calendar: utc)
        var rng = SplitMix64(seed: 5)
        let plan = try await service.travelPlan(days: 6, warmth: .mild, scenario: .casual, using: &rng)
        XCTAssertEqual(plan.underwearCount, 5)
        XCTAssertEqual(plan.socksCount, 5)
        XCTAssertTrue(plan.showsCapHint)
        XCTAssertEqual(Set(plan.suggestion.map(\.id)).count, plan.suggestion.count)
        XCTAssertGreaterThanOrEqual(plan.suggestion.count, 3)
        await expectServiceError(.invalid("")) { _ = try await service.travelPlan(days: 0, warmth: .mild, scenario: .casual, using: &rng) }
    }
}

final class SettingsServiceTests: XCTestCase {
    func testProfileDefaultsUpdateAndValidation() async throws {
        let service = SettingsService(store: try makeStore(), now: { fixedNow })
        let initial = try await service.profile()
        XCTAssertEqual(initial, Profile())
        XCTAssertEqual(initial.gender, "unspecified")
        let saved = try await service.updateProfile(Profile(heightCm: 172.5, weightKg: 60, age: 30, gender: "female"))
        let loaded = try await service.profile()
        XCTAssertEqual(loaded, saved)
        await expectServiceError(.invalid("")) { _ = try await service.updateProfile(Profile(age: 121)) }
        await expectServiceError(.invalid("")) { _ = try await service.updateProfile(Profile(gender: "robot")) }
        await expectServiceError(.invalid("")) { _ = try await service.updateProfile(Profile(heightCm: -1)) }
        await expectServiceError(.invalid("")) { _ = try await service.updateProfile(Profile(weightKg: .nan)) }
    }
}
