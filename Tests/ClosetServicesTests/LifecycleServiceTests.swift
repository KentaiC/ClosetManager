import XCTest
import ClosetCore
import ClosetStorage
@testable import ClosetServices

final class LifecycleServiceTests: XCTestCase {
    var store: ClosetStore!
    var service: LifecycleService!
    let top = storedItem(.tee), bottom = storedItem(.jeans), shoes = storedItem(.sneakers), outer = storedItem(.jacket)

    override func setUp() async throws {
        store = try makeStore()
        service = LifecycleService(store: store, now: { fixedNow })
        try await insert(store, [top, bottom, shoes, outer])
    }

    var members: [SlottedItemID] {
        [SlottedItemID(itemID: outer.id, slot: .outerwear), SlottedItemID(itemID: top.id, slot: .top),
         SlottedItemID(itemID: bottom.id, slot: .bottom), SlottedItemID(itemID: shoes.id, slot: .shoes)]
    }

    func testWearKeepsSingleActiveRecordAndDoesNotChangeItems() async throws {
        let first = try await service.wear(members: members)
        let second = try await service.wear(members: Array(members.prefix(2)))
        let records = try await store.read { try $0.wearRecords() }
        XCTAssertEqual(records.filter(\.isActive).map(\.id), [second.id])
        XCTAssertTrue(records.contains { $0.id == first.id && !$0.isActive })
        XCTAssertEqual(second.date, fixedNow)
        XCTAssertEqual(second.members, Array(members.prefix(2)))
        let statuses = try await store.read { try $0.items().map(\.status) }
        XCTAssertTrue(statuses.allSatisfy { $0 == .inWardrobe })
    }

    func testWearValidatesInput() async {
        await expectServiceError(.invalid("")) { _ = try await self.service.wear(members: []) }
        await expectServiceError(.notFound("")) { _ = try await self.service.wear(members: [SlottedItemID(itemID: UUID())]) }
        await expectServiceError(.invalid("")) {
            _ = try await self.service.wear(members: [SlottedItemID(itemID: self.top.id), SlottedItemID(itemID: self.top.id)])
        }
        await expectServiceError(.notFound("")) { _ = try await self.service.wear(members: self.members, outfitID: UUID()) }
    }

    func testWearOutfitUsesItsCurrentMembers() async throws {
        let outfit = try await OutfitService(store: store, now: { fixedNow }).create(
            name: nil, isFavorite: true, source: .generated, targetScenario: .casual, targetWarmthLevel: .mild, members: members)
        let record = try await service.wearOutfit(id: outfit.id)
        XCTAssertEqual(record.outfitID, outfit.id)
        XCTAssertEqual(record.members, members)
        await expectServiceError(.notFound("")) { _ = try await self.service.wearOutfit(id: UUID()) }
    }

    func testTakeOffMovesCheckedItemsToLaundry() async throws {
        let record = try await service.wear(members: members)
        let result = try await service.takeOff(recordID: record.id, laundryItemIDs: [top.id, bottom.id])
        XCTAssertFalse(result.isActive)
        let items = try await store.read { Dictionary(uniqueKeysWithValues: try $0.items().map { ($0.id, $0) }) }
        XCTAssertEqual(items[top.id]?.status, .inLaundry)
        XCTAssertEqual(items[top.id]?.laundryEntryDate, fixedNow)
        XCTAssertEqual(items[bottom.id]?.status, .inLaundry)
        XCTAssertEqual(items[outer.id]?.status, .inWardrobe)
        XCTAssertNil(items[outer.id]?.laundryEntryDate)
        XCTAssertEqual(items[top.id]?.updatedAt, fixedNow)
        let active = try await store.read { try $0.activeWearRecord() }
        XCTAssertNil(active)

        await expectServiceError(.conflict("")) { _ = try await self.service.takeOff(recordID: record.id, laundryItemIDs: []) }
        await expectServiceError(.notFound("")) { _ = try await self.service.takeOff(recordID: UUID(), laundryItemIDs: []) }
    }

    func testTakeOffRejectsItemsOutsideTheRecord() async throws {
        let record = try await service.wear(members: Array(members.prefix(1)))
        await expectServiceError(.invalid("")) { _ = try await self.service.takeOff(recordID: record.id, laundryItemIDs: [self.shoes.id]) }
    }

    /// 与 App 相同：从收藏穿着时不检查状态，脱下时未勾选的单品回到衣橱（审计 H-03，保持现状）。
    func testTakeOffReturnsUncheckedLuggageItemToWardrobe_AuditH03() async throws {
        let packed = storedItem(.trenchCoat, status: .inLuggage)
        try await insert(store, [packed])
        let record = try await service.wear(members: [SlottedItemID(itemID: packed.id, slot: .outerwear)])
        _ = try await service.takeOff(recordID: record.id, laundryItemIDs: [])
        let item = try await store.read { try $0.item(id: packed.id) }
        XCTAssertEqual(item?.status, .inWardrobe)
    }

    func testReturnFromLaundryOnlyAcceptsLaundryItems() async throws {
        let dirty = storedItem(.shirt, status: .inLaundry, laundry: Date(timeIntervalSince1970: 1_780_000_000))
        try await insert(store, [dirty])
        let returned = try await service.returnFromLaundry(itemIDs: [dirty.id])
        XCTAssertEqual(returned.first?.status, .inWardrobe)
        XCTAssertNil(returned.first?.laundryEntryDate)
        await expectServiceError(.conflict("")) { _ = try await self.service.returnFromLaundry(itemIDs: [self.top.id]) }
        await expectServiceError(.invalid("")) { _ = try await self.service.returnFromLaundry(itemIDs: []) }
    }

    func testPackAndUnpackKeepLaundryDate() async throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let dirty = storedItem(.shirt, status: .inLaundry, laundry: date)
        try await insert(store, [dirty])
        let packed = try await service.pack(itemIDs: [dirty.id, top.id])
        XCTAssertTrue(packed.allSatisfy { $0.status == .inLuggage })
        XCTAssertEqual(packed.first { $0.id == dirty.id }?.laundryEntryDate, date)
        let count = try await service.unpackAll()
        XCTAssertEqual(count, 2)
        let after = try await store.read { try $0.item(id: dirty.id) }
        XCTAssertEqual(after?.status, .inWardrobe)
        XCTAssertEqual(after?.laundryEntryDate, date)
    }

    func testDeleteWearRecord() async throws {
        let record = try await service.wear(members: members)
        try await service.deleteWearRecord(id: record.id)
        await expectServiceError(.notFound("")) { try await self.service.deleteWearRecord(id: record.id) }
    }
}
