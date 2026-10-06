import XCTest
import ClosetCore
@testable import ClosetStorage
@testable import ClosetServices

final class BackupExportTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")

    private func importedStore(_ store: ClosetStore? = nil) async throws -> ClosetStore {
        let store = try store ?? makeStore()
        _ = try await BackupImporter(store: store).importBackup(try Data(contentsOf: Self.fixture), mode: .overwrite, dryRun: false)
        return store
    }

    private func snapshot(_ store: ClosetStore) async throws -> ([StoredItem], [StoredOutfit], [StoredWearRecord]) {
        try await store.read { s in
            (try s.items().sorted { $0.id.uuidString < $1.id.uuidString }, try s.outfits().sorted { $0.id.uuidString < $1.id.uuidString },
             try s.wearRecords().sorted { $0.id.uuidString < $1.id.uuidString })
        }
    }

    func testExportMatchesTheAppFileAndRoundTrips() async throws {
        let source = try await importedStore()
        let exported = try await BackupExporter(store: source).export()

        // 与样例文件逐项比较：同一份数据导出后，每个字段（含图片字节）都与原文件一致。
        let decoder = WardrobeBackup.makeDecoder()
        let original = try decoder.decode(WardrobeBackup.Bundle.self, from: Data(contentsOf: Self.fixture))
        let bundle = try decoder.decode(WardrobeBackup.Bundle.self, from: exported)
        XCTAssertEqual(bundle.version, 1)
        let encoder = WardrobeBackup.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json<T: Encodable>(_ values: [T], id: (T) -> UUID) throws -> [String] {
            try values.sorted { id($0).uuidString < id($1).uuidString }.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        }
        XCTAssertEqual(try json(bundle.items, id: \.id), try json(original.items, id: \.id))
        XCTAssertEqual(try json(bundle.outfits, id: \.id), try json(original.outfits, id: \.id))
        XCTAssertEqual(try json(bundle.wearRecords, id: \.id), try json(original.wearRecords, id: \.id))

        let target = try makeStore()
        _ = try await BackupImporter(store: target).importBackup(exported, mode: .overwrite, dryRun: false)
        let before = try await snapshot(source), after = try await snapshot(target)
        XCTAssertEqual(after.0, before.0)
        XCTAssertEqual(after.1, before.1)
        XCTAssertEqual(after.2, before.2)
    }

    func testFileNameMatchesTheApp() {
        XCTAssertEqual(BackupExporter.fileName(at: Date(timeIntervalSince1970: 1_791_331_200)), "ClosetBackup-2026-10-07T00-00-00Z.wardrobe")
    }

    func testRestoreDryRunWritesNothing() async throws {
        let store = try makeStore()
        let report = try await BackupRestoreService(store: store).restore(try Data(contentsOf: Self.fixture), mode: .merge, apply: false)
        XCTAssertTrue(report.dryRun)
        XCTAssertFalse(report.applied)
        XCTAssertEqual(report.items.toImport, 3)
        let count = try await store.read { try $0.counts().items }
        XCTAssertEqual(count, 0)
    }

    func testApplyingSavesTheCurrentDataFirstAndKeepsFiveSnapshots() async throws {
        let directory = DataDirectory(root: FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)"))
        let store = try ClosetStore(directory: directory)
        let data = try Data(contentsOf: Self.fixture)
        var clock = 1_791_331_200.0

        let start = clock
        let first = try await BackupRestoreService(store: store, now: { Date(timeIntervalSince1970: start) }).restore(data, mode: .overwrite, apply: true)
        XCTAssertTrue(first.applied)
        XCTAssertNil(first.preImportBackup, "nothing to save in an empty store")

        for _ in 0..<6 {
            clock += 60
            let now = clock
            let report = try await BackupRestoreService(store: store, now: { Date(timeIntervalSince1970: now) }).restore(data, mode: .overwrite, apply: true)
            XCTAssertTrue(report.applied)
            let name = try XCTUnwrap(report.preImportBackup)
            let saved = try Data(contentsOf: directory.beforeImportBackupsURL.appendingPathComponent(name))
            let bundle = try WardrobeBackup.makeDecoder().decode(WardrobeBackup.Bundle.self, from: saved)
            XCTAssertEqual(bundle.items.count, 3)
        }
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.beforeImportBackupsURL.path).sorted()
        XCTAssertEqual(kept.count, BackupRestoreService.keptSnapshots)
        XCTAssertEqual(kept.last, BackupExporter.fileName(at: Date(timeIntervalSince1970: clock)))
    }

    func testRejectedImportsDoNotSaveOrWrite() async throws {
        let directory = DataDirectory(root: FileManager.default.temporaryDirectory.appendingPathComponent("reject-\(UUID().uuidString)"))
        let store = try await importedStore(try ClosetStore(directory: directory))
        var json = try XCTUnwrap(String(data: Data(contentsOf: Self.fixture), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"category\": \"top\"", with: "\"category\": \"hats\"")
        let report = try await BackupRestoreService(store: store).restore(Data(json.utf8), mode: .overwrite, apply: true)
        XCTAssertFalse(report.applied)
        XCTAssertFalse(report.errors.isEmpty)
        XCTAssertNil(report.preImportBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.beforeImportBackupsURL.path))

        do {
            _ = try await BackupRestoreService(store: store).restore(Data("not json".utf8), mode: .merge, apply: true)
            XCTFail("expected unreadable")
        } catch ImportError.unreadable {}
        let count = try await store.read { try $0.counts().items }
        XCTAssertEqual(count, 3)
    }
}
