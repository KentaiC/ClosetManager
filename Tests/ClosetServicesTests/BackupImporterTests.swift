import XCTest
import ClosetCore
import ClosetStorage
@testable import ClosetServices

final class BackupImporterTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")

    var store: ClosetStore!
    var importer: BackupImporter!

    override func setUp() async throws {
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("importer-\(UUID().uuidString)")
        store = try ClosetStore(inMemoryWithMediaRoot: media)
        importer = BackupImporter(store: store)
    }

    func encode(_ bundle: WardrobeBackup.Bundle) throws -> Data { try WardrobeBackup.makeEncoder().encode(bundle) }

    func item(_ id: UUID = UUID(), category: String = "top", subtype: String? = "tee", status: String = "inWardrobe",
              scenarios: [String] = ["casual"], warmth: Int = 30, levels: [String] = [], laundry: Date? = nil,
              processed: Data? = nil, original: Data? = nil) -> WardrobeBackup.ItemDTO {
        WardrobeBackup.ItemDTO(id: id, name: "", category: category, subtype: subtype, scenarios: scenarios, status: status,
                               isWaterproof: false, laundryEntryDate: laundry, dominantColor: StoredColor(red: 0.9, green: 0.1, blue: 0.1),
                               secondaryColor: nil, warmthScore: warmth, warmthLevels: levels, seasons: [], brand: nil, notes: nil,
                               createdAt: Date(timeIntervalSince1970: 1_750_000_000), updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                               processedImageBase64: processed?.base64EncodedString(), originalImageBase64: original?.base64EncodedString())
    }

    func record(_ id: UUID = UUID(), date: TimeInterval, active: Bool, items: [UUID] = [], outfit: UUID? = nil) -> WardrobeBackup.WearRecordDTO {
        WardrobeBackup.WearRecordDTO(id: id, date: Date(timeIntervalSince1970: date), isActive: active, outfitID: outfit,
                                     itemIDs: items, notes: nil, createdAt: Date(timeIntervalSince1970: date))
    }

    // MARK: - 样例文件

    func testFixtureImportsCompletely() async throws {
        let data = try Data(contentsOf: Self.fixture)
        let report = try await importer.importBackup(data, mode: .overwrite, dryRun: false)
        XCTAssertTrue(report.applied)
        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(report.items, ImportCounts(inBackup: 3, toImport: 3, skippedExisting: 0))
        XCTAssertEqual(report.outfits.toImport, 1)
        XCTAssertEqual(report.wearRecords.toImport, 2)
        XCTAssertEqual(report.imageCount, 2)
        // 样例中的牛仔裤有两个保暖标签，与保暖度 50 对应的「温和」一致；第三件的标签与保暖度 60 一致。
        XCTAssertEqual(report.warnings.map(\.code), [])

        let catalog = CatalogService(store: store)
        let items = try await catalog.items()
        XCTAssertEqual(items.count, 3)
        let tee = try XCTUnwrap(items.first { $0.subtype == .tee })
        XCTAssertEqual(tee.processedImage?.format, .png)
        XCTAssertEqual(tee.originalImage?.format, .jpeg)
        XCTAssertEqual(tee.scenarios, [.work, .casual])
        XCTAssertEqual(tee.seasons, [.spring, .summer])
        XCTAssertEqual(tee.dominantColorCategory, ColorCategory.classify(tee.dominantColor))
        XCTAssertEqual(try store.media.read(XCTUnwrap(tee.processedImage)).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        let jeans = try XCTUnwrap(items.first { $0.subtype == .jeans })
        XCTAssertEqual(jeans.warmthLevels, [.cool, .mild], "stored as-is")
        XCTAssertEqual(jeans.seasons, [], "explicit empty seasons kept, as the app does")
        XCTAssertNotNil(jeans.laundryEntryDate)

        let outfits = try await catalog.outfits(favoritesOnly: true)
        XCTAssertEqual(outfits.first?.items.map(\.subtype), [.tee, .jeans, .boots], "member order preserved")
        let records = try await catalog.wearRecords()
        XCTAssertEqual(records.map(\.record.isActive), [true, false], "newest first")
        XCTAssertNil(records[0].record.outfitID)
        XCTAssertEqual(records[0].record.notes, "只穿了上衣")
    }

    func testDryRunWritesNothing() async throws {
        let data = try Data(contentsOf: Self.fixture)
        let report = try await importer.importBackup(data, mode: .overwrite, dryRun: true)
        XCTAssertFalse(report.applied)
        XCTAssertEqual(report.items.toImport, 3)
        let counts = try await CatalogService(store: store).counts()
        XCTAssertEqual(counts, StoreCounts(items: 0, outfits: 0, wearRecords: 0, media: 0))
        XCTAssertTrue(store.media.storedHashes().isEmpty)
    }

    func testUnreadableFile() async {
        do {
            _ = try await importer.importBackup(Data("not json".utf8), mode: .merge, dryRun: true)
            XCTFail("expected unreadable")
        } catch ImportError.unreadable {
        } catch { XCTFail("\(error)") }
    }

    // MARK: - 覆盖与合并

    func testOverwriteReplacesEverythingAndCleansMedia() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1])
        let first = WardrobeBackup.Bundle(items: [item(processed: png)], outfits: [], wearRecords: [])
        _ = try await importer.importBackup(try encode(first), mode: .overwrite, dryRun: false)
        XCTAssertEqual(store.media.storedHashes().count, 1)
        let second = WardrobeBackup.Bundle(items: [item(), item()], outfits: [], wearRecords: [])
        _ = try await importer.importBackup(try encode(second), mode: .overwrite, dryRun: false)
        let counts = try await CatalogService(store: store).counts()
        XCTAssertEqual(counts.items, 2)
        XCTAssertEqual(counts.media, 0)
        XCTAssertTrue(store.media.storedHashes().isEmpty, "old image removed")
    }

    func testOverwriteWithSameFileIsIdempotent() async throws {
        let data = try Data(contentsOf: Self.fixture)
        _ = try await importer.importBackup(data, mode: .overwrite, dryRun: false)
        let before = try await CatalogService(store: store).items()
        _ = try await importer.importBackup(data, mode: .overwrite, dryRun: false)
        let after = try await CatalogService(store: store).items()
        XCTAssertEqual(before, after)
        XCTAssertEqual(store.media.storedHashes().count, 2)
    }

    func testMergeSkipsExistingIDsWithoutUpdating() async throws {
        let id = UUID()
        _ = try await importer.importBackup(try encode(.init(items: [item(id, warmth: 30)], outfits: [], wearRecords: [])), mode: .overwrite, dryRun: false)
        let bundle = WardrobeBackup.Bundle(items: [item(id, warmth: 90), item()], outfits: [], wearRecords: [])
        let report = try await importer.importBackup(try encode(bundle), mode: .merge, dryRun: false)
        XCTAssertEqual(report.items, ImportCounts(inBackup: 2, toImport: 1, skippedExisting: 1))
        let kept = try await CatalogService(store: store).item(id: id)
        XCTAssertEqual(kept?.warmthScore, 30, "existing record is not updated, same as the app")
    }

    func testMergeLinksToExistingItems() async throws {
        let existingItem = UUID()
        _ = try await importer.importBackup(try encode(.init(items: [item(existingItem)], outfits: [], wearRecords: [])), mode: .overwrite, dryRun: false)
        let outfit = WardrobeBackup.OutfitDTO(id: UUID(), name: "o", isFavorite: true, source: "generated", targetScenario: nil,
                                              targetWarmthLevel: nil, itemIDs: [existingItem], createdAt: .now, updatedAt: .now)
        let report = try await importer.importBackup(try encode(.init(items: [], outfits: [outfit], wearRecords: [])), mode: .merge, dryRun: false)
        XCTAssertEqual(report.warnings, [])
        let outfits = try await CatalogService(store: store).outfits(favoritesOnly: true)
        XCTAssertEqual(outfits.first?.items.map(\.id), [existingItem])
    }

    // MARK: - 严格校验

    func testUnknownValuesAreRejectedNotReplaced() async throws {
        let bad = item(category: "hats", subtype: nil, status: "lost", scenarios: ["party"], levels: ["tropical"])
        let bundle = WardrobeBackup.Bundle(items: [bad], outfits: [], wearRecords: [])
        let preview = try await importer.importBackup(try encode(bundle), mode: .overwrite, dryRun: true)
        XCTAssertEqual(preview.errors.map(\.code), [.invalidValue, .invalidValue, .invalidValue, .invalidValue])
        XCTAssertEqual(preview.items.toImport, 0)
        do {
            _ = try await importer.importBackup(try encode(bundle), mode: .overwrite, dryRun: false)
            XCTFail("expected rejection")
        } catch ImportError.rejected(let report) {
            XCTAssertFalse(report.applied)
        }
        let counts = try await CatalogService(store: store).counts()
        XCTAssertEqual(counts.items, 0)
    }

    func testRejectsSubtypeMismatchOutOfRangeWarmthBadBase64DuplicatesAndVersion() async throws {
        var badBase64 = item()
        badBase64.processedImageBase64 = "%%%"
        let dup = UUID()
        let bundle = WardrobeBackup.Bundle(items: [item(category: "top", subtype: "jeans"), item(warmth: 0), badBase64, item(dup), item(dup)],
                                           outfits: [], wearRecords: [])
        let report = try await importer.importBackup(try encode(bundle), mode: .overwrite, dryRun: true)
        XCTAssertEqual(Set(report.errors.map(\.code)), [.subtypeCategoryMismatch, .warmthScoreOutOfRange, .invalidImageData, .duplicateID])

        let future = WardrobeBackup.Bundle(version: 2, items: [], outfits: [], wearRecords: [])
        let versionReport = try await importer.importBackup(try encode(future), mode: .merge, dryRun: true)
        XCTAssertEqual(versionReport.errors.map(\.code), [.unsupportedVersion])
    }

    // MARK: - 可自动处理的问题

    func testMultipleActiveRecordsKeepNewest() async throws {
        let older = record(date: 100, active: true), newer = record(date: 200, active: true)
        let report = try await importer.importBackup(try encode(.init(items: [], outfits: [], wearRecords: [older, newer])),
                                                     mode: .overwrite, dryRun: false)
        XCTAssertEqual(report.warnings.map(\.code), [.multipleActiveRecords])
        XCTAssertEqual(report.warnings.first?.id, older.id.uuidString)
        let active = try await CatalogService(store: store).wearRecords(activeOnly: true)
        XCTAssertEqual(active.map(\.record.id), [newer.id])
    }

    func testMergeDoesNotStealActiveRecord() async throws {
        let current = record(date: 100, active: true)
        _ = try await importer.importBackup(try encode(.init(items: [], outfits: [], wearRecords: [current])), mode: .overwrite, dryRun: false)
        let incoming = record(date: 300, active: true)
        let report = try await importer.importBackup(try encode(.init(items: [], outfits: [], wearRecords: [incoming])), mode: .merge, dryRun: false)
        XCTAssertEqual(report.warnings.map(\.code), [.activeRecordConflict])
        let active = try await CatalogService(store: store).wearRecords(activeOnly: true)
        XCTAssertEqual(active.map(\.record.id), [current.id])
    }

    func testMissingReferencesAndDuplicateMembersAreDropped() async throws {
        let a = UUID(), ghost = UUID(), ghostOutfit = UUID()
        let outfit = WardrobeBackup.OutfitDTO(id: UUID(), name: "o", isFavorite: false, source: "manual", targetScenario: "work",
                                              targetWarmthLevel: "cold", itemIDs: [a, ghost, a], createdAt: .now, updatedAt: .now)
        let wear = record(date: 10, active: false, items: [ghost, a], outfit: ghostOutfit)
        let report = try await importer.importBackup(try encode(.init(items: [item(a)], outfits: [outfit], wearRecords: [wear])),
                                                     mode: .overwrite, dryRun: false)
        XCTAssertEqual(report.warnings.map(\.code), [.missingItemReference, .duplicateMember, .missingOutfitReference, .missingItemReference])
        let records = try await CatalogService(store: store).wearRecords()
        XCTAssertEqual(records.first?.record.itemIDs, [a])
        XCTAssertNil(records.first?.record.outfitID)
        let outfits = try await CatalogService(store: store).outfits(favoritesOnly: false)
        XCTAssertEqual(outfits.first?.outfit.source, .manual)
        XCTAssertEqual(outfits.first?.outfit.targetWarmthLevel, .cold)
    }

    func testWarningsForLaundryStateUnknownImageAndWarmthLevels() async throws {
        let laundryWithoutDate = item(status: "inLaundry", laundry: nil)
        let notAnImage = item(original: Data("hello".utf8))
        let legacyLevels = item(warmth: 50, levels: ["cold"])
        let report = try await importer.importBackup(try encode(.init(items: [laundryWithoutDate, notAnImage, legacyLevels], outfits: [], wearRecords: [])),
                                                     mode: .overwrite, dryRun: false)
        XCTAssertEqual(report.warnings.map(\.code), [.inconsistentLaundryState, .unknownImageFormat, .inconsistentWarmthLevels])
        let stored = try await CatalogService(store: store).item(id: notAnImage.id)
        XCTAssertEqual(stored?.originalImage?.format, .unknown, "kept as-is")
    }

    func testEmptyWarmthLevelsAreDerivedLikeTheApp() async throws {
        let dto = item(warmth: 90, levels: [])
        _ = try await importer.importBackup(try encode(.init(items: [dto], outfits: [], wearRecords: [])), mode: .overwrite, dryRun: false)
        let stored = try await CatalogService(store: store).item(id: dto.id)
        XCTAssertEqual(stored?.warmthLevels, [.frigid])
    }
}
