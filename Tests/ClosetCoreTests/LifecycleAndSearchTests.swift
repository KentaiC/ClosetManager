import XCTest
import ClosetCore

final class ItemLifecycleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let old = Date(timeIntervalSince1970: 1_700_000_000)

    func testTakeOff() {
        let worn = ItemLifecycle.State(status: .inWardrobe, laundryEntryDate: nil)
        XCTAssertEqual(ItemLifecycle.takeOff(worn, sentToLaundry: true, now: now), .init(status: .inLaundry, laundryEntryDate: now))
        XCTAssertEqual(ItemLifecycle.takeOff(worn, sentToLaundry: false, now: now), .init(status: .inWardrobe, laundryEntryDate: nil))
    }

    /// 审计 H-03：不在衣橱中的单品脱下时状态与入袋时间都不变。
    func testTakeOffLeavesItemsOutsideTheWardrobeUnchanged() {
        let luggage = ItemLifecycle.State(status: .inLuggage, laundryEntryDate: old)
        let laundry = ItemLifecycle.State(status: .inLaundry, laundryEntryDate: old)
        for sent in [true, false] {
            XCTAssertEqual(ItemLifecycle.takeOff(luggage, sentToLaundry: sent, now: now), luggage)
            XCTAssertEqual(ItemLifecycle.takeOff(laundry, sentToLaundry: sent, now: now), laundry)
        }
    }

    func testCheckWearAllowsCompleteWardrobeOutfit() {
        let items = [ItemLifecycle.WearCandidate(title: "上装", category: .top, status: .inWardrobe),
                     ItemLifecycle.WearCandidate(title: "下装", category: .bottom, status: .inWardrobe),
                     ItemLifecycle.WearCandidate(title: "鞋子", category: .shoes, status: .inWardrobe)]
        let check = ItemLifecycle.checkWear(items, requireComplete: true)
        XCTAssertTrue(check.isAllowed)
        XCTAssertNil(check.message)
    }

    func testCheckWearRejectsItemsOutsideTheWardrobe() {
        let items = [ItemLifecycle.WearCandidate(title: "白色T恤", category: .top, status: .inLaundry),
                     ItemLifecycle.WearCandidate(title: "牛仔裤", category: .bottom, status: .inWardrobe),
                     ItemLifecycle.WearCandidate(title: "防水靴", category: .shoes, status: .inLuggage)]
        let check = ItemLifecycle.checkWear(items, requireComplete: true)
        XCTAssertFalse(check.isAllowed)
        XCTAssertEqual(check.unavailable.map(\.title), ["白色T恤", "防水靴"])
        XCTAssertEqual(check.missingRequired, [])
        XCTAssertEqual(check.message, "这套穿搭中有单品不在衣橱：白色T恤在洗衣袋，防水靴在行李箱。请先放回衣橱再穿。")
    }

    func testCheckWearReportsMissingRequiredOnlyWhenAsked() {
        let items = [ItemLifecycle.WearCandidate(title: "风衣", category: .outerwear, status: .inLuggage),
                     ItemLifecycle.WearCandidate(title: "鞋子", category: .shoes, status: .inWardrobe)]
        let complete = ItemLifecycle.checkWear(items, requireComplete: true)
        XCTAssertEqual(complete.missingRequired, [.top, .bottom])
        XCTAssertEqual(complete.message, "这套穿搭缺少：上装、下装。相关单品可能已被删除。这套穿搭中有单品不在衣橱：风衣在行李箱。请先放回衣橱再穿。")
        let partial = ItemLifecycle.checkWear(items, requireComplete: false)
        XCTAssertEqual(partial.missingRequired, [])
        XCTAssertEqual(partial.message, "这套穿搭中有单品不在衣橱：风衣在行李箱。请先放回衣橱再穿。")
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
