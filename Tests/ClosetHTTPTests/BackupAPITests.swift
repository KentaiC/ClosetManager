import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetCore
@testable import ClosetStorage
import ClosetServices
@testable import ClosetHTTP

final class BackupAPITests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")
    static let guardHeader: HTTPFields = [RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web"]
    static let now = Date(timeIntervalSince1970: 1_791_331_200)

    var directory: DataDirectory!
    var store: ClosetStore!

    override func setUp() async throws {
        directory = DataDirectory(root: FileManager.default.temporaryDirectory.appendingPathComponent("backup-api-\(UUID().uuidString)"))
        store = try ClosetStore(directory: directory)
    }

    func app() -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765), now: { Self.now }))
    }

    static func object(_ response: TestResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    }

    func testImportPreviewApplyAndExport() async throws {
        let file = try Data(contentsOf: Self.fixture)
        let store = self.store!, directory = self.directory!
        try await app().test(.router) { client in
            let unguarded = try await client.execute(uri: "/api/v1/backup/import?mode=merge", method: .post, body: ByteBuffer(data: file))
            XCTAssertEqual(unguarded.status, .forbidden)

            let preview = try Self.object(try await client.execute(uri: "/api/v1/backup/import?mode=merge", method: .post,
                                                                    headers: Self.guardHeader, body: ByteBuffer(data: file)))
            XCTAssertEqual(preview["dryRun"] as? Bool, true)
            XCTAssertEqual(preview["applied"] as? Bool, false)
            XCTAssertEqual((preview["items"] as? [String: Any])?["toImport"] as? Int, 3)
            let empty = try await store.read { try $0.counts().items }
            XCTAssertEqual(empty, 0)

            let applied = try Self.object(try await client.execute(uri: "/api/v1/backup/import?mode=merge&apply=true", method: .post,
                                                                    headers: Self.guardHeader, body: ByteBuffer(data: file)))
            XCTAssertEqual(applied["applied"] as? Bool, true)
            XCTAssertNil(applied["preImportBackup"], "nothing to save before the first import")

            let again = try Self.object(try await client.execute(uri: "/api/v1/backup/import?mode=overwrite&apply=true", method: .post,
                                                                  headers: Self.guardHeader, body: ByteBuffer(data: file)))
            let snapshot = try XCTUnwrap(again["preImportBackup"] as? String)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.beforeImportBackupsURL.appendingPathComponent(snapshot).path))
            XCTAssertFalse(snapshot.contains("/"), "only the file name is returned, never a local path")

            let exportBlocked = try await client.execute(uri: "/api/v1/backup/export", method: .post)
            XCTAssertEqual(exportBlocked.status, .forbidden)
            let export = try await client.execute(uri: "/api/v1/backup/export", method: .post, headers: Self.guardHeader)
            XCTAssertEqual(export.status, .ok)
            XCTAssertEqual(export.headers[.contentDisposition], "attachment; filename=\"ClosetBackup-2026-10-07T00-00-00Z.wardrobe\"")
            XCTAssertEqual(export.headers[.cacheControl], "no-store")
            let bundle = try WardrobeBackup.makeDecoder().decode(WardrobeBackup.Bundle.self, from: Data(export.body.readableBytesView))
            XCTAssertEqual(bundle.items.count, 3)
            XCTAssertEqual(bundle.wearRecords.count, 2)
        }
    }

    func testRejectsUnreadableFilesAndBadParameters() async throws {
        let store = self.store!
        try await app().test(.router) { client in
            let unreadable = try await client.execute(uri: "/api/v1/backup/import?apply=true", method: .post,
                                                      headers: Self.guardHeader, body: ByteBuffer(string: "<html>"))
            XCTAssertEqual(unreadable.status, .badRequest)
            XCTAssertEqual(((try Self.object(unreadable))["error"] as? [String: Any])?["code"] as? String, "invalid_backup")

            let badMode = try await client.execute(uri: "/api/v1/backup/import?mode=replace", method: .post, headers: Self.guardHeader, body: ByteBuffer(string: "{}"))
            XCTAssertEqual(badMode.status, .badRequest)
            let badApply = try await client.execute(uri: "/api/v1/backup/import?apply=yes", method: .post, headers: Self.guardHeader, body: ByteBuffer(string: "{}"))
            XCTAssertEqual(badApply.status, .badRequest)
            let count = try await store.read { try $0.counts().items }
            XCTAssertEqual(count, 0)
        }
    }
}
