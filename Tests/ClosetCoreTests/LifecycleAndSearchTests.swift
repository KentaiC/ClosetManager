import XCTest
import ClosetCore

final class ItemLifecycleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let old = Date(timeIntervalSince1970: 1_700_000_000)

    func testTakeOff() {
        XCTAssertEqual(ItemLifecycle.takeOff(sentToLaundry: true, now: now), .init(status: .inLaundry, laundryEntryDate: now))
        XCTAssertEqual(ItemLifecycle.takeOff(sentToLaundry: false, now: now), .init(status: .inWardrobe, laundryEntryDate: nil))
    }

    func testReturnFromLaundryClearsDate() {
        XCTAssertEqual(ItemLifecycle.returnFromLaundry(), .init(status: .inWardrobe, laundryEntryDate: nil))
    }

    func testPackAndUnpackKeepLaundryDate() {
        let laundry = ItemLifecycle.State(status: .inLaundry, laundryEntryDate: old)
        XCTAssertEqual(ItemLifecycle.pack(laundry), .init(status: .inLuggage, laundryEntryDate: old))
        XCTAssertEqual(ItemLifecycle.unpack(.init(status: .inLuggage, laundryEntryDate: old)), .init(status: .inWardrobe, laundryEntryDate: old))
    }
}

final class TravelSuggestionTests: XCTestCase {
    func testSuggestionDeduplicatesAcrossDraftsInOrder() {
        let tee = TestItem(.tee), shirt = TestItem(.shirt), jeans = TestItem(.jeans), boots = TestItem(.boots)
        let result = OutfitGenerationResult(drafts: [
            OutfitDraftOf(top: tee, bottom: jeans, shoes: boots),
            OutfitDraftOf(top: shirt, bottom: jeans, shoes: boots),
        ], missingRequired: [])
        XCTAssertEqual(TravelService.packingSuggestion(from: result).map(\.id), [tee.id, jeans.id, boots.id, shirt.id])
        XCTAssertEqual(TravelService.packingSuggestion(from: OutfitGenerationResult<TestItem>(drafts: [], missingRequired: [.top])).count, 0)
    }
}

final class WardrobeSearchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testEachCriterion() {
        let item = TestItem(.tee, scenarios: [.work], waterproof: true, color: .blue)
        XCTAssertTrue(WardrobeSearch().matches(item, lastWornDate: nil))
        XCTAssertTrue(WardrobeSearch(scenario: .work).matches(item, lastWornDate: nil))
        XCTAssertFalse(WardrobeSearch(scenario: .sport).matches(item, lastWornDate: nil))
        XCTAssertTrue(WardrobeSearch(waterproofOnly: true).matches(item, lastWornDate: nil))
        XCTAssertFalse(WardrobeSearch(waterproofOnly: true).matches(TestItem(.tee), lastWornDate: nil))
        XCTAssertTrue(WardrobeSearch(colorCategory: .blue).matches(item, lastWornDate: nil))
        XCTAssertFalse(WardrobeSearch(colorCategory: .red).matches(item, lastWornDate: nil))
    }

    /// 与 App 相同：没有穿着记录的单品（包括刚录入的）也算「未穿」，见审计 M-17。
    func testUnwornUsesLastWearDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let cutoff = WardrobeSearch.unwornCutoff(days: 90, now: now, calendar: utc)
        XCTAssertEqual(cutoff, now.addingTimeInterval(-90 * 86_400))
        let search = WardrobeSearch(unwornSince: cutoff)
        let item = TestItem(.tee)
        XCTAssertTrue(search.matches(item, lastWornDate: nil))
        XCTAssertTrue(search.matches(item, lastWornDate: cutoff.addingTimeInterval(-1)))
        XCTAssertFalse(search.matches(item, lastWornDate: cutoff))
        XCTAssertFalse(search.matches(item, lastWornDate: now))
    }
}
