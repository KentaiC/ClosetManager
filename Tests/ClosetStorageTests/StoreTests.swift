import XCTest
import ClosetCore
@testable import ClosetStorage

final class StoreTests: XCTestCase {
    var store: ClosetStore!

    override func setUp() async throws {
        store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
    }

    func testItemRoundTripIncludingMediaAndOptionalFields() async throws {
        let processed = try store.media.write(pngBytes)
        let original = try store.media.write(jpegBytes)
        var item = makeItem(.hoodie, status: .inLaundry, processed: processed, original: original)
        item.notes = "备注"
        let saved = item
        try await store.transaction { try $0.insertItem(saved) }
        let loaded = try await store.read { try $0.item(id: saved.id) }
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded?.processedImage?.format, .png)
        XCTAssertEqual(loaded?.originalImage?.format, .jpeg)
        XCTAssertEqual(loaded?.displayImage, processed)
    }

    func testItemWithoutSubtypeAndSecondaryColor() async throws {
        var item = makeItem(nil, category: .bottom)
        item.secondaryColor = nil
        item.scenarios = []
        item.seasons = []
        let saved = item
        try await store.transaction { try $0.insertItem(saved) }
        let loaded = try await store.read { try $0.item(id: saved.id) }
        XCTAssertEqual(loaded, saved)
    }

    func testItemsAreFilteredAndOrderedNewestFirst() async throws {
        let old = makeItem(.tee, created: 100), new = makeItem(.jeans, created: 200)
        let laundry = makeItem(.shirt, status: .inLaundry, created: 300)
        try await store.transaction { s in for i in [old, new, laundry] { try s.insertItem(i) } }
        let all = try await store.read { try $0.items() }
        XCTAssertEqual(all.map(\.id), [laundry.id, new.id, old.id])
        let tops = try await store.read { try $0.items(ItemFilter(status: .inWardrobe, category: .top)) }
        XCTAssertEqual(tops.map(\.id), [old.id])
        let byIDs = try await store.read { try $0.items(ItemFilter(ids: [old.id, laundry.id])) }
        XCTAssertEqual(Set(byIDs.map(\.id)), [old.id, laundry.id])
    }

    func testCheckConstraintRejectsUnknownCategory() async throws {
        do {
            try await store.transaction { s in
                try s.db.run("""
                    INSERT INTO items (id, name, category, status, dominant_red, dominant_green, dominant_blue, dominant_alpha,
                        dominant_color_category, warmth_score, warmth_levels, seasons, created_at, updated_at)
                    VALUES ('X', 'n', 'hat', 'inWardrobe', 0, 0, 0, 1, 'gray', 50, '[]', '[]', 0, 0);
                    """)
            }
            XCTFail("expected constraint violation")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraintViolation, "\(error)")
        }
    }

    func testSubtypeMustBelongToCategory() async throws {
        var item = makeItem(.jeans)
        item.category = .top
        let invalid = item
        do {
            try await store.transaction { try $0.insertItem(invalid) }
            XCTFail("expected foreign key violation")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraintViolation, "\(error)")
        }
    }

    func testWarmthScoreRange() async throws {
        var item = makeItem()
        item.warmthScore = 101
        let invalid = item
        do {
            try await store.transaction { try $0.insertItem(invalid) }
            XCTFail("expected check violation")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraintViolation)
        }
    }

    func testOnlyOneActiveWearRecord() async throws {
        let a = StoredWearRecord(id: UUID(), date: .now, isActive: true, outfitID: nil, members: [], notes: nil, createdAt: .now)
        var b = a
        b.id = UUID()
        try await store.transaction { try $0.insertWearRecord(a) }
        do {
            try await store.transaction { [b] in try $0.insertWearRecord(b) }
            XCTFail("expected unique violation")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraintViolation)
        }
        let active = try await store.read { try $0.activeWearRecord() }
        XCTAssertEqual(active?.id, a.id)
    }

    func testDeletingItemKeepsOutfitAndRecordButRemovesMembership() async throws {
        let top = makeItem(.tee), bottom = makeItem(.jeans)
        // 时间以 Unix 秒存储，测试使用整秒时间点以便逐字段比较。
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let outfit = StoredOutfit(id: UUID(), name: "收藏穿搭", isFavorite: true, source: .generated, targetScenario: .casual,
                                  targetWarmthLevel: .mild, members: [SlottedItemID(itemID: top.id, slot: .top), SlottedItemID(itemID: bottom.id)],
                                  createdAt: t0, updatedAt: t0)
        let record = StoredWearRecord(id: UUID(), date: t0, isActive: false, outfitID: outfit.id,
                                      members: [SlottedItemID(itemID: bottom.id), SlottedItemID(itemID: top.id)], notes: "n", createdAt: t0)
        try await store.transaction { s in
            try s.insertItem(top); try s.insertItem(bottom); try s.insertOutfit(outfit); try s.insertWearRecord(record)
        }
        let loadedOutfit = try await store.read { try $0.outfits(favoritesOnly: true).first }
        XCTAssertEqual(loadedOutfit, outfit, "member order and slots preserved")
        let loadedRecord = try await store.read { try $0.wearRecords().first }
        XCTAssertEqual(loadedRecord, record)

        try await store.transaction { try $0.db.run("DELETE FROM items WHERE id = ?;", [.text(top.id.uuidString)]) }
        let afterOutfit = try await store.read { try $0.outfits().first }
        XCTAssertEqual(afterOutfit?.itemIDs, [bottom.id])
        let afterRecord = try await store.read { try $0.wearRecords().first }
        XCTAssertEqual(afterRecord?.itemIDs, [bottom.id])

        try await store.transaction { try $0.db.run("DELETE FROM outfits;") }
        let recordWithoutOutfit = try await store.read { try $0.wearRecords().first }
        XCTAssertNil(recordWithoutOutfit?.outfitID)
    }

    func testTransactionRollsBackOnError() async throws {
        struct Boom: Error {}
        let item = makeItem()
        do {
            try await store.transaction { s -> Void in try s.insertItem(item); throw Boom() }
        } catch is Boom {}
        let count = try await store.read { try $0.counts().items }
        XCTAssertEqual(count, 0)
    }

    func testDeleteAllWardrobeData() async throws {
        let item = makeItem()
        let outfit = StoredOutfit(id: UUID(), name: "o", isFavorite: false, source: .manual, targetScenario: nil, targetWarmthLevel: nil,
                                  members: [SlottedItemID(itemID: item.id)], createdAt: .now, updatedAt: .now)
        try await store.transaction { s in try s.insertItem(item); try s.insertOutfit(outfit) }
        try await store.transaction { try $0.deleteAllWardrobeData() }
        let counts = try await store.read { try $0.counts() }
        XCTAssertEqual(counts.items + counts.outfits + counts.wearRecords, 0)
    }
}

final class StoreWriteTests: XCTestCase {
    var store: ClosetStore!

    override func setUp() async throws {
        store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
    }

    func testUpdateItemReplacesMutableFields() async throws {
        let original = makeItem(.tee)
        try await store.transaction { try $0.insertItem(original) }
        var changed = original
        changed.name = "新名字"
        changed.category = .bottom
        changed.subtype = .jeans
        changed.scenarios = [.sport]
        changed.secondaryColor = nil
        changed.updatedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let updated = changed
        let found = try await store.transaction { try $0.updateItem(updated) }
        XCTAssertTrue(found)
        let loaded = try await store.read { try $0.item(id: original.id) }
        XCTAssertEqual(loaded, updated)
        var ghost = makeItem()
        ghost.id = UUID()
        let ghostItem = ghost
        let missing = try await store.transaction { try $0.updateItem(ghostItem) }
        XCTAssertFalse(missing)
    }

    func testStateUpdateDeleteAndLastWorn() async throws {
        let a = makeItem(.tee), b = makeItem(.jeans)
        let t1 = Date(timeIntervalSince1970: 1_760_000_000), t2 = Date(timeIntervalSince1970: 1_770_000_000)
        try await store.transaction { s in
            try s.insertItem(a); try s.insertItem(b)
            try s.insertWearRecord(StoredWearRecord(id: UUID(), date: t1, isActive: false, outfitID: nil, members: [SlottedItemID(itemID: a.id)], notes: nil, createdAt: t1))
            try s.insertWearRecord(StoredWearRecord(id: UUID(), date: t2, isActive: true, outfitID: nil, members: [SlottedItemID(itemID: a.id)], notes: nil, createdAt: t2))
        }
        let lastWorn = try await store.read { try $0.lastWornDates() }
        XCTAssertEqual(lastWorn, [a.id: t2])

        try await store.transaction { try $0.updateItemState(id: b.id, state: .init(status: .inLaundry, laundryEntryDate: t2), updatedAt: t2) }
        let laundry = try await store.read { try $0.item(id: b.id) }
        XCTAssertEqual(laundry?.status, .inLaundry)
        XCTAssertEqual(laundry?.laundryEntryDate, t2)

        try await store.transaction { try $0.deactivateWearRecords() }
        let active = try await store.read { try $0.activeWearRecord() }
        XCTAssertNil(active)

        let deleted = try await store.transaction { try $0.deleteItem(id: a.id) }
        XCTAssertTrue(deleted)
        let records = try await store.read { try $0.wearRecords() }
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.members.isEmpty })
    }

    func testSettingsUpsert() async throws {
        let t = Date(timeIntervalSince1970: 1)
        try await store.transaction { try $0.putSetting("profile", json: #"{"age":1}"#, updatedAt: t) }
        try await store.transaction { try $0.putSetting("profile", json: #"{"age":2}"#, updatedAt: t) }
        let value = try await store.read { try $0.setting("profile") }
        XCTAssertEqual(value, #"{"age":2}"#)
        let missing = try await store.read { try $0.setting("nothing") }
        XCTAssertNil(missing)
        do {
            try await store.transaction { try $0.putSetting("bad", json: "not json", updatedAt: t) }
            XCTFail("invalid JSON must be rejected")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraintViolation)
        }
    }
}
