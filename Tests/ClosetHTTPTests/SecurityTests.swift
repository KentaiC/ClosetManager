import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetCore
@testable import ClosetStorage
import ClosetServices
@testable import ClosetHTTP

/// 对全部 API 路由做的安全检查，对应审计 8.4 的要求：
/// 写请求必须通过来源校验，外部 Host 一律拒绝，参数格式错误返回 400 而不是 500，内部错误不暴露本机路径。
final class SecurityTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")
    static let tee = "7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E"
    static let record = "C3D4E5F6-A7B8-4C9D-8E0F-2A3B4C5D6E7F"
    static let outfit = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
    static let sha = String(repeating: "e", count: 64)

    /// 全部会改变数据或导出数据的路由。新增写路由时应同时加入这里。
    static let writeRoutes: [(HTTPRequest.Method, String)] = [
        (.post, "/api/v1/items"), (.put, "/api/v1/items/\(tee)"), (.delete, "/api/v1/items/\(tee)"),
        (.post, "/api/v1/images"), (.post, "/api/v1/images/\(sha)/process"),
        (.post, "/api/v1/wear-records"), (.post, "/api/v1/wear-records/\(record)/take-off"), (.delete, "/api/v1/wear-records/\(record)"),
        (.post, "/api/v1/laundry/return"),
        (.post, "/api/v1/outfits"), (.post, "/api/v1/outfits/\(outfit)/wear"), (.delete, "/api/v1/outfits/\(outfit)"),
        (.post, "/api/v1/travel/pack"), (.post, "/api/v1/travel/unpack-all"),
        (.put, "/api/v1/settings/profile"),
        (.post, "/api/v1/backup/export"), (.post, "/api/v1/backup/import"),
    ]

    /// 全部只读路由。
    static let readRoutes: [String] = [
        "/api/v1/health", "/api/v1/meta", "/api/v1/items", "/api/v1/items/\(tee)", "/api/v1/items/\(tee)/image",
        "/api/v1/images/\(sha)", "/api/v1/outfits", "/api/v1/wear-records", "/api/v1/wear-records/active",
        "/api/v1/naming/default-name?category=top&color=FFFFFF", "/api/v1/outfit-suggestions?warmth=mild&scenario=casual",
        "/api/v1/analytics", "/api/v1/search", "/api/v1/travel/plan?days=3&warmth=mild&scenario=casual",
        "/api/v1/settings/profile", "/api/v1/similar-items",
    ]

    var store: ClosetStore!

    override func setUp() async throws {
        store = try ClosetStore(inMemoryWithMediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent("sec-\(UUID().uuidString)"))
        _ = try await BackupImporter(store: store).importBackup(try Data(contentsOf: Self.fixture), mode: .overwrite, dryRun: false)
    }

    func app(policy: LoopbackPolicy? = nil) -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765), policy: policy))
    }

    static func errorCode(_ response: TestResponse) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any]
        return (object?["error"] as? [String: Any])?["code"] as? String
    }

    func testEveryWriteRouteRequiresTheClientHeaderAndChangesNothing() async throws {
        let store = self.store!
        let before = try await store.read { try $0.counts() }
        try await app().test(.router) { client in
            for (method, path) in Self.writeRoutes {
                let response = try await client.execute(uri: path, method: method, body: ByteBuffer(string: "{}"))
                XCTAssertEqual(response.status, .forbidden, "\(method) \(path)")
                XCTAssertEqual(Self.errorCode(response), "request_rejected", "\(method) \(path)")

                let crossSite = try await client.execute(uri: path, method: method, headers: [
                    RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web", HTTPField.Name("Sec-Fetch-Site")!: "cross-site",
                ], body: ByteBuffer(string: "{}"))
                XCTAssertEqual(crossSite.status, .forbidden, "cross-site \(method) \(path)")
            }
        }
        let after = try await store.read { try $0.counts() }
        XCTAssertEqual(after, before)
    }

    func testEveryRouteRejectsAForeignHost() async throws {
        try await app(policy: LoopbackPolicy(port: 8765, allowedHosts: ["127.0.0.1"])).test(.router) { client in
            for path in Self.readRoutes {
                let response = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(response.status, .forbidden, path)
                XCTAssertEqual(Self.errorCode(response), "host_not_allowed", path)
            }
            for (method, path) in Self.writeRoutes {
                let response = try await client.execute(uri: path, method: method, headers: [
                    RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web",
                ], body: ByteBuffer(string: "{}"))
                XCTAssertEqual(response.status, .forbidden, "\(method) \(path)")
            }
        }
    }

    func testMalformedIdentifiersAreClientErrors() async throws {
        let guardHeader: HTTPFields = [RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web", .contentType: "application/json"]
        try await app().test(.router) { client in
            for (method, path) in [
                (HTTPRequest.Method.get, "/api/v1/items/not-a-uuid"), (.get, "/api/v1/items/not-a-uuid/image"),
                (.put, "/api/v1/items/not-a-uuid"), (.delete, "/api/v1/items/not-a-uuid"),
                (.post, "/api/v1/wear-records/not-a-uuid/take-off"), (.delete, "/api/v1/wear-records/not-a-uuid"),
                (.post, "/api/v1/outfits/not-a-uuid/wear"), (.delete, "/api/v1/outfits/not-a-uuid"),
            ] {
                let response = try await client.execute(uri: path, method: method, headers: guardHeader, body: ByteBuffer(string: "{}"))
                XCTAssertEqual(response.status, .badRequest, "\(method) \(path)")
            }
            for path in ["/api/v1/images/not-a-hash", "/api/v1/images/\(String(repeating: "Z", count: 64))", "/api/v1/images/..%2F..%2Fcloset.sqlite"] {
                let response = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(response.status, .notFound, path)
            }
            let process = try await client.execute(uri: "/api/v1/images/../process", method: .post, headers: guardHeader)
            XCTAssertTrue([.notFound, .badRequest].contains(process.status), "got \(process.status)")
        }
    }

    func testInternalErrorsDoNotRevealLocalPaths() async throws {
        let store = self.store!
        // 删除磁盘上的图片文件，制造一次存储层错误。
        let item = try await store.read { try $0.item(id: UUID(uuidString: Self.tee)!) }
        let ref = try XCTUnwrap(item?.originalImage)
        try FileManager.default.removeItem(at: store.media.url(for: ref))
        try await app().test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/items/\(Self.tee)/image?variant=original", method: .get)
            XCTAssertEqual(response.status, .internalServerError)
            let body = String(decoding: Data(response.body.readableBytesView), as: UTF8.self)
            XCTAssertEqual(Self.errorCode(response), "internal_error")
            XCTAssertTrue(body.contains("服务器内部错误。"))
            XCTAssertFalse(body.contains(FileManager.default.temporaryDirectory.path), body)
            XCTAssertFalse(body.contains(ref.sha256), body)
        }
    }

    func testApiResponsesAreNotCachedExceptVersionedImages() async throws {
        try await app().test(.router) { client in
            for path in ["/api/v1/health", "/api/v1/items", "/api/v1/items/\(Self.tee)", "/api/v1/settings/profile"] {
                let response = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(response.headers[.cacheControl], "no-store", path)
            }
            let item = try JSONSerialization.jsonObject(with: Data(try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .get).body.readableBytesView)) as? [String: Any]
            let url = try XCTUnwrap(((item?["images"] as? [String: Any])?["display"] as? [String: Any])?["url"] as? String)
            let versioned = try await client.execute(uri: url, method: .get)
            XCTAssertEqual(versioned.headers[.cacheControl], "private, max-age=31536000, immutable")
            let unversioned = try await client.execute(uri: "/api/v1/items/\(Self.tee)/image", method: .get)
            XCTAssertEqual(unversioned.headers[.cacheControl], "no-cache")
        }
    }
}
