import XCTest
import ClosetCore

/// `.wardrobe` 备份格式契约：键名、日期格式、可选字段。
final class WardrobeBackupContractTests: XCTestCase {
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")

    /// 审计 C-01：版本号不是当前版本的备份在写入前被拒绝。
    func testCheckVersionRejectsOtherVersions() throws {
        var bundle = WardrobeBackup.Bundle(items: [], outfits: [], wearRecords: [])
        XCTAssertNoThrow(try WardrobeBackup.checkVersion(bundle))
        for version in [0, 2] {
            bundle.version = version
            XCTAssertThrowsError(try WardrobeBackup.checkVersion(bundle)) { error in
                XCTAssertEqual(error as? WardrobeBackup.UnsupportedVersion, WardrobeBackup.UnsupportedVersion(version: version))
                XCTAssertEqual(error.localizedDescription, "备份文件版本为 \(version)，当前只支持版本 1。请更新到能读取该版本的 App。")
            }
        }
    }

    func testFixtureDecodes() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let bundle = try WardrobeBackup.makeDecoder().decode(WardrobeBackup.Bundle.self, from: data)
        XCTAssertEqual(bundle.version, 1)
        XCTAssertEqual(bundle.items.count, 3)
        XCTAssertEqual(bundle.outfits.count, 1)
        XCTAssertEqual(bundle.wearRecords.count, 2)
        XCTAssertEqual(bundle.items[0].subtype, "tee")
        XCTAssertNil(bundle.items[0].laundryEntryDate)
        XCTAssertNotNil(bundle.items[1].laundryEntryDate)
        XCTAssertNil(bundle.wearRecords[1].outfitID)
        XCTAssertEqual(bundle.items[1].secondaryColor?.alpha, 1)
        XCTAssertEqual(bundle.items[0].processedImageBase64.flatMap { Data(base64Encoded: $0) }?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testEncodedKeyNamesMatchContract() throws {
        let item = WardrobeBackup.ItemDTO(
            id: UUID(), name: "n", category: "top", subtype: "tee", scenarios: ["casual"], status: "inWardrobe",
            isWaterproof: true, laundryEntryDate: Date(timeIntervalSince1970: 0), dominantColor: StoredColor(red: 1, green: 1, blue: 1),
            secondaryColor: StoredColor(red: 0, green: 0, blue: 0), warmthScore: 10, warmthLevels: ["hot"], seasons: ["summer"],
            brand: "b", notes: "x", createdAt: .now, updatedAt: .now, processedImageBase64: "AA==", originalImageBase64: "AA=="
        )
        let outfit = WardrobeBackup.OutfitDTO(id: UUID(), name: "o", isFavorite: true, source: "manual", targetScenario: "work",
                                              targetWarmthLevel: "mild", itemIDs: [item.id], createdAt: .now, updatedAt: .now)
        let record = WardrobeBackup.WearRecordDTO(id: UUID(), date: .now, isActive: true, outfitID: outfit.id, itemIDs: [item.id],
                                                  notes: "r", createdAt: .now)
        let data = try WardrobeBackup.makeEncoder().encode(WardrobeBackup.Bundle(items: [item], outfits: [outfit], wearRecords: [record]))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["version", "items", "outfits", "wearRecords"])
        let itemKeys = try XCTUnwrap((root["items"] as? [[String: Any]])?.first).keys
        XCTAssertEqual(Set(itemKeys), [
            "id", "name", "category", "subtype", "scenarios", "status", "isWaterproof", "laundryEntryDate",
            "dominantColor", "secondaryColor", "warmthScore", "warmthLevels", "seasons", "brand", "notes",
            "createdAt", "updatedAt", "processedImageBase64", "originalImageBase64",
        ])
        let outfitKeys = try XCTUnwrap((root["outfits"] as? [[String: Any]])?.first).keys
        XCTAssertEqual(Set(outfitKeys), ["id", "name", "isFavorite", "source", "targetScenario", "targetWarmthLevel", "itemIDs", "createdAt", "updatedAt"])
        let recordKeys = try XCTUnwrap((root["wearRecords"] as? [[String: Any]])?.first).keys
        XCTAssertEqual(Set(recordKeys), ["id", "date", "isActive", "outfitID", "itemIDs", "notes", "createdAt"])
    }

    func testDatesUseISO8601AndUUIDsAreUppercase() throws {
        let id = UUID(uuidString: "7a2c1d9e-3b4f-4c5a-9d6e-1f2a3b4c5d6e")!
        let record = WardrobeBackup.WearRecordDTO(id: id, date: Date(timeIntervalSince1970: 1_782_892_800), isActive: false,
                                                  outfitID: nil, itemIDs: [], notes: nil, createdAt: Date(timeIntervalSince1970: 0))
        let json = String(decoding: try WardrobeBackup.makeEncoder().encode(record), as: UTF8.self)
        XCTAssertTrue(json.contains("\"2026-07-01T08:00:00Z\""), json)
        XCTAssertTrue(json.contains("7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E"), json)
        XCTAssertFalse(json.contains("outfitID"), "nil optionals are omitted")
    }

    func testUnsupportedShapeFailsToDecode() {
        let data = Data(#"{"items":[],"outfits":[],"wearRecords":[]}"#.utf8)
        XCTAssertThrowsError(try WardrobeBackup.makeDecoder().decode(WardrobeBackup.Bundle.self, from: data), "version is required")
    }

    func testRestoreModeRawValues() {
        XCTAssertEqual(RestoreMode.allCases.map(\.rawValue), ["overwrite", "merge"])
    }

    func testItemDefaults() {
        XCTAssertEqual(ItemDefaults.resolvedWarmthLevels([], warmthScore: 90), [.frigid])
        XCTAssertEqual(ItemDefaults.resolvedWarmthLevels([.cool, .mild], warmthScore: 90), [.cool, .mild])
        XCTAssertEqual(ItemDefaults.defaultName(color: StoredColor(red: 0, green: 0.5, blue: 0), subtype: .shorts, category: .bottom), "绿色短裤")
        XCTAssertEqual(ItemDefaults.defaultName(color: StoredColor(red: 181 / 255, green: 145 / 255, blue: 102 / 255), subtype: .overcoat, category: .outerwear), "橙色大衣")
    }
}

final class WardrobeRulesTests: XCTestCase {
    func testLaundryRetentionWarningAfterFourDays() {
        let entry = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(WardrobeRules.isLaundryRetentionWarning(entryDate: nil, now: entry))
        XCTAssertFalse(WardrobeRules.isLaundryRetentionWarning(entryDate: entry, now: entry.addingTimeInterval(4 * 86_400)))
        XCTAssertTrue(WardrobeRules.isLaundryRetentionWarning(entryDate: entry, now: entry.addingTimeInterval(4 * 86_400 + 1)))
        XCTAssertEqual(WardrobeRules.unwornDays, 90)
    }

    func testDisplayTitleFallsBackToCategory() {
        XCTAssertEqual(ItemDefaults.displayTitle(name: "", category: .socks), "袜子")
        XCTAssertEqual(ItemDefaults.displayTitle(name: "白T", category: .top), "白T")
    }
}
