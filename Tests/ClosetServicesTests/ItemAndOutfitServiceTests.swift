import XCTest
import ClosetCore
import ClosetStorage
@testable import ClosetServices

final class ItemServiceTests: XCTestCase {
    var store: ClosetStore!
    var service: ItemService!

    override func setUp() async throws {
        store = try makeStore()
        service = ItemService(store: store, now: { fixedNow })
    }

    func edit(name: String = "", category: ClosetCore.Category = .bottom, subtype: Subtype? = .shorts, status: ItemStatus = .inWardrobe,
              warmth: Int = 90, color: StoredColor = StoredColor(red: 0, green: 0.5, blue: 0)) -> ItemEdit {
        ItemEdit(name: name, category: category, subtype: subtype, scenarios: [.sport, .work], warmthScore: warmth,
                 seasons: [.winter, .spring], status: status, isWaterproof: true, brand: "", notes: "备注", dominantColor: color)
    }

    func testUpdateFollowsTheAppEditorRules() async throws {
        let laundryDate = Date(timeIntervalSince1970: 1_780_000_000)
        let item = storedItem(.tee, status: .inLaundry, laundry: laundryDate)
        try await insert(store, [item])
        let updated = try await service.update(id: item.id, with: edit())
        XCTAssertEqual(updated.name, "绿色短裤", "empty name uses colour + subtype")
        XCTAssertEqual(updated.warmthLevels, [.frigid])
        XCTAssertEqual(updated.scenarios, [.work, .sport], "stored in enum order like the app")
        XCTAssertEqual(updated.seasons, [.spring, .winter])
        XCTAssertEqual(updated.dominantColorCategory, .green)
        XCTAssertNil(updated.brand, "empty brand becomes nil")
        XCTAssertEqual(updated.notes, "备注")
        XCTAssertEqual(updated.updatedAt, fixedNow)
        XCTAssertEqual(updated.createdAt, item.createdAt)
        XCTAssertEqual(updated.status, .inWardrobe)
        XCTAssertEqual(updated.laundryEntryDate, laundryDate, "audit M-01: status edits keep the laundry date, as in the app")
        let stored = try await store.read { try $0.item(id: item.id) }
        XCTAssertEqual(stored, updated)

        let named = try await service.update(id: item.id, with: edit(name: "我的短裤"))
        XCTAssertEqual(named.name, "我的短裤")
    }

    func testUpdateValidation() async throws {
        let item = storedItem(.tee)
        try await insert(store, [item])
        await expectServiceError(.invalid("")) { _ = try await self.service.update(id: item.id, with: self.edit(category: .top, subtype: .jeans)) }
        await expectServiceError(.invalid("")) { _ = try await self.service.update(id: item.id, with: self.edit(warmth: 0)) }
        await expectServiceError(.invalid("")) {
            _ = try await self.service.update(id: item.id, with: self.edit(color: StoredColor(red: 2, green: 0, blue: 0)))
        }
        await expectServiceError(.notFound("")) { _ = try await self.service.update(id: UUID(), with: self.edit()) }
    }

    func testDeleteRemovesItemAndUnusedImages() async throws {
        let ref = try store.media.write(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7]))
        var item = storedItem(.tee)
        item.processedImage = ref
        let saved = item
        try await insert(store, [saved])
        try await service.delete(id: saved.id)
        XCTAssertTrue(store.media.storedHashes().isEmpty)
        await expectServiceError(.notFound("")) { try await self.service.delete(id: saved.id) }
    }
}

final class OutfitServiceTests: XCTestCase {
    func testSuggestionsAreDeterministicAndSlotted() async throws {
        let store = try makeStore()
        let items = [storedItem(.tee, warmth: 20), storedItem(.hoodie, warmth: 45), storedItem(.jeans), storedItem(.sneakers),
                     storedItem(.overcoat, warmth: 80), storedItem(.crewSocks), storedItem(.hat)]
        try await insert(store, items)
        let service = OutfitService(store: store, now: { fixedNow })
        var a = SplitMix64(seed: 3), b = SplitMix64(seed: 3)
        let first = try await service.suggestions(warmth: .cold, scenario: .casual, requireWaterproof: false, using: &a)
        let second = try await service.suggestions(warmth: .cold, scenario: .casual, requireWaterproof: false, using: &b)
        XCTAssertEqual(first.drafts.map { $0.members.map(\.item.id) }, second.drafts.map { $0.members.map(\.item.id) })
        XCTAssertFalse(first.drafts.isEmpty)
        for draft in first.drafts {
            let slots = draft.members.map(\.slot)
            let order: [OutfitSlot] = [.outerwear, .midLayer, .top, .bottom, .socks, .shoes, .accessory]
            XCTAssertEqual(slots, order.filter(slots.contains), "outer to inner, top to bottom")
            XCTAssertTrue(slots.contains(.top) && slots.contains(.bottom) && slots.contains(.shoes))
        }
        var c = SplitMix64(seed: 1)
        let missing = try await service.suggestions(warmth: .mild, scenario: .formal, requireWaterproof: true, using: &c)
        XCTAssertEqual(missing.missingRequired, [.top, .bottom, .shoes, .outerwear])
    }

    func testCreateAndDelete() async throws {
        let store = try makeStore()
        let top = storedItem(.tee), bottom = storedItem(.jeans), shoes = storedItem(.sneakers)
        try await insert(store, [top, bottom, shoes])
        let service = OutfitService(store: store, now: { fixedNow })
        let members = [SlottedItemID(itemID: top.id, slot: .top), SlottedItemID(itemID: bottom.id, slot: .bottom), SlottedItemID(itemID: shoes.id, slot: .shoes)]
        let manual = try await service.create(name: nil, isFavorite: true, source: .manual, targetScenario: nil, targetWarmthLevel: nil, members: members)
        XCTAssertEqual(manual.name, "收藏穿搭")
        XCTAssertEqual(manual.source, .manual, "deliberate fix of audit M-05 in the web version")
        let stored = try await store.read { try $0.outfits(favoritesOnly: true) }
        XCTAssertEqual(stored, [manual])
        await expectServiceError(.notFound("")) {
            _ = try await service.create(name: "x", isFavorite: true, source: .generated, targetScenario: nil, targetWarmthLevel: nil,
                                         members: [SlottedItemID(itemID: UUID())])
        }
        try await service.delete(id: manual.id)
        await expectServiceError(.notFound("")) { try await service.delete(id: manual.id) }
    }
}
