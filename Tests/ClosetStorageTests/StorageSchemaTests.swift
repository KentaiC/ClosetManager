import XCTest
import ClosetCore
@testable import ClosetStorage

final class StorageSchemaTests: XCTestCase {
    func testMigrationValueListsMatchCoreEnums() {
        XCTAssertEqual(Migrations.categoryValues, ClosetCore.Category.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.statusValues, ItemStatus.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.scenarioValues, Scenario.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.warmthLevelValues, WarmthLevel.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.seasonValues, Season.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.sourceValues, OutfitSource.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.colorCategoryValues, ColorCategory.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.slotValues, OutfitSlot.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.mediaVariantValues, MediaVariantKind.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.subtypeCategories.map(\.0), Subtype.allCases.map(\.rawValue))
        XCTAssertEqual(Migrations.subtypeCategories.map(\.1), Subtype.allCases.map(\.category.rawValue))
    }

    func testFreshDatabaseIsAtLatestVersion() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let version = try await store.schemaVersion()
        XCTAssertEqual(version, Migrations.all.last?.version)
    }

    func testReopeningFileDatabaseDoesNotReapplyMigrations() async throws {
        let directory = DataDirectory(root: try makeTemporaryDirectory())
        let item = makeItem()
        do {
            let store = try ClosetStore(directory: directory)
            try await store.transaction { try $0.insertItem(item) }
        }
        let reopened = try ClosetStore(directory: directory)
        let count = try await reopened.read { try $0.counts().items }
        XCTAssertEqual(count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.preMigrationBackupsURL.path), "no upgrade, no backup")
    }

    func testVersionOneDatabaseUpgradesWithBackupAndKeepsItsData() async throws {
        let directory = DataDirectory(root: try makeTemporaryDirectory())
        try directory.prepare()
        let item = makeItem(original: MediaRef(sha256: String(repeating: "b", count: 64), format: .jpeg, byteCount: 3))
        do {
            // 模拟第四阶段发布时的数据库：只执行到版本 1。
            let db = try SQLiteDatabase(path: directory.databaseURL.path)
            try MigrationRunner.migrate(db, backupBeforeUpgrade: nil, migrations: Array(Migrations.all.prefix(1)))
            try db.transaction { try StoreSession(db: db).insertItem(item) }
        }
        let store = try ClosetStore(directory: directory)
        let version = try await store.schemaVersion()
        XCTAssertEqual(version, 2)
        let stored = try await store.read { try $0.item(id: item.id) }
        XCTAssertEqual(stored, item)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.preMigrationBackupsURL.path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].hasPrefix("closet-v1-"))
    }

    func testUpgradeTakesBackupFirst() throws {
        let root = try makeTemporaryDirectory()
        let db = try SQLiteDatabase(path: root.appendingPathComponent("db.sqlite").path)
        let v1 = Migration(version: 1, name: "one", sql: "CREATE TABLE a (x INTEGER);")
        let v2 = Migration(version: 2, name: "two", sql: "CREATE TABLE b (y INTEGER);")
        XCTAssertEqual(try MigrationRunner.migrate(db, backupBeforeUpgrade: root.appendingPathComponent("bk"), migrations: [v1]), [1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bk").path), "fresh database needs no backup")
        try db.run("INSERT INTO a VALUES (7);")
        XCTAssertEqual(try MigrationRunner.migrate(db, backupBeforeUpgrade: root.appendingPathComponent("bk"), migrations: [v1, v2]), [2])
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("bk").path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].hasPrefix("closet-v1-"))
        let copy = try SQLiteDatabase(path: root.appendingPathComponent("bk").appendingPathComponent(backups[0]).path)
        XCTAssertEqual(try copy.query("SELECT x FROM a;").first?.int("x"), 7)
        XCTAssertEqual(try MigrationRunner.currentVersion(copy), 1)
    }

    func testNewerSchemaIsRefused() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner.migrate(db, backupBeforeUpgrade: nil)
        try db.run("INSERT INTO schema_migrations (version, name, applied_at) VALUES (99, 'future', 0);")
        XCTAssertThrowsError(try MigrationRunner.migrate(db, backupBeforeUpgrade: nil)) { error in
            XCTAssertEqual(error as? StorageError, .schemaTooNew(found: 99, supported: Migrations.all.last!.version))
        }
    }

    func testFailedMigrationLeavesVersionUnchanged() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let broken = Migration(version: 1, name: "broken", sql: "CREATE TABLE ok (x INTEGER); CREATE TABLE ok (x INTEGER);")
        XCTAssertThrowsError(try MigrationRunner.migrate(db, backupBeforeUpgrade: nil, migrations: [broken]))
        XCTAssertEqual(try MigrationRunner.currentVersion(db), 0)
        XCTAssertTrue(try db.query("SELECT name FROM sqlite_master WHERE name = 'ok';").isEmpty, "rolled back")
    }
}
