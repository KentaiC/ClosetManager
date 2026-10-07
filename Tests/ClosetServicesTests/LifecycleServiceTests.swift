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

    /// 审计 H-03：穿着前每件单品都必须在衣橱中。被拒绝时不新建记录，也不结束正在穿的记录。
    func testWearRejectsItemsOutsideTheWardrobe_AuditH03() async throws {
        let packed = storedItem(.trenchCoat, status: .inLuggage)
        try await insert(store, [packed])
        let current = try await service.wear(members: members)
        do {
            _ = try await service.wear(members: [SlottedItemID(itemID: packed.id, slot: .outerwear), SlottedItemID(itemID: top.id, slot: .top)])
            XCTFail("expected conflict")
        } catch let error as ServiceError {
            XCTAssertEqual(error, .conflict("这套穿搭中有单品不在衣橱：外套在行李箱。请先放回衣橱再穿。"))
        }
        let records = try await store.read { try $0.wearRecords() }
        XCTAssertEqual(records.map(\.id), [current.id])
        XCTAssertTrue(records[0].isActive)
    }

    /// 审计 H-03：穿已保存的穿搭时还要求上装、下装、鞋子齐全。
    func testWearOutfitRejectsIncompleteOutfit_AuditH03() async throws {
        let outfit = try await OutfitService(store: store, now: { fixedNow }).create(
            name: nil, isFavorite: true, source: .manual, targetScenario: nil, targetWarmthLevel: nil,
            members: [SlottedItemID(itemID: top.id, slot: .top), SlottedItemID(itemID: shoes.id, slot: .shoes)])
        do {
            _ = try await service.wearOutfit(id: outfit.id)
            XCTFail("expected conflict")
        } catch let error as ServiceError {
            XCTAssertEqual(error, .conflict("这套穿搭缺少：下装。相关单品可能已被删除。"))
        }
        let records = try await store.read { try $0.wearRecords() }
        XCTAssertTrue(records.isEmpty)
    }

    /// 审计 H-03：已有的正在穿记录里若有单品后来被装进行李箱或洗衣袋，脱下时这些单品的状态与入袋时间保持不变。
    func testTakeOffLeavesItemsOutsideTheWardrobeUnchanged_AuditH03() async throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let packed = storedItem(.trenchCoat, status: .inLuggage, laundry: date)
        let dirty = storedItem(.shirt, status: .inLaundry, laundry: date)
        try await insert(store, [packed, dirty])
        let recordID = UUID()
        let record = StoredWearRecord(
            id: recordID, date: date, isActive: true, outfitID: nil,
            members: [SlottedItemID(itemID: packed.id, slot: .outerwear), SlottedItemID(itemID: dirty.id, slot: .top),
                      SlottedItemID(itemID: bottom.id, slot: .bottom)],
            notes: nil, createdAt: date)
        try await store.transaction { s in try s.insertWearRecord(record) }
        let result = try await service.takeOff(recordID: recordID, laundryItemIDs: [packed.id, bottom.id])
        XCTAssertFalse(result.isActive)
        let items = try await store.read { Dictionary(uniqueKeysWithValues: try $0.items().map { ($0.id, $0) }) }
        XCTAssertEqual(items[packed.id]?.status, .inLuggage)
        XCTAssertEqual(items[packed.id]?.laundryEntryDate, date)
        XCTAssertEqual(items[packed.id]?.updatedAt, packed.updatedAt)
        XCTAssertEqual(items[dirty.id]?.status, .inLaundry)
        XCTAssertEqual(items[dirty.id]?.laundryEntryDate, date)
        XCTAssertEqual(items[bottom.id]?.status, .inLaundry)
        XCTAssertEqual(items[bottom.id]?.laundryEntryDate, fixedNow)
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
