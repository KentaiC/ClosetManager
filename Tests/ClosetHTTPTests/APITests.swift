import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetCore
@testable import ClosetStorage
import ClosetServices
@testable import ClosetHTTP

final class APITests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")
    static let teeID = "7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E"
    static let jeansID = "8B3D2E0F-4C5A-4D6B-8E7F-2A3B4C5D6E7F"

    var store: ClosetStore!

    override func setUp() async throws {
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("api-\(UUID().uuidString)")
        store = try ClosetStore(inMemoryWithMediaRoot: media)
        _ = try await BackupImporter(store: store).importBackup(try Data(contentsOf: Self.fixture), mode: .overwrite, dryRun: false)
    }

    func app(policy: LoopbackPolicy? = nil) -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765), policy: policy))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ response: TestResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(response.body.readableBytesView))
    }

    static func errorCode(_ response: TestResponse) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: [String: String]]
        return object?["error"]?["code"] ?? ""
    }

    // MARK: - 基础接口

    func testHealthAndSecurityHeaders() async throws {
        try await app().test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/health", method: .get)
            XCTAssertEqual(response.status, .ok)
            let health = try Self.decode(APIHealth.self, response)
            XCTAssertEqual(health.status, "ok")
            XCTAssertEqual(health.schemaVersion, 2)
            XCTAssertEqual(health.counts.items, 3)
            XCTAssertFalse(health.capabilities.backgroundRemoval)
            XCTAssertEqual(response.headers[.contentSecurityPolicy], SecurityHeadersMiddleware<BasicRequestContext>.contentSecurityPolicy)
            XCTAssertEqual(response.headers[HTTPField.Name("X-Content-Type-Options")!], "nosniff")
            XCTAssertEqual(response.headers[HTTPField.Name("X-Frame-Options")!], "DENY")
            XCTAssertEqual(response.headers[.cacheControl], "no-store")
        }
    }

    func testMetaExposesCoreDisplayNamesAndRules() async throws {
        try await app().test(.router) { client in
            let meta = try Self.decode(APIMeta.self, try await client.execute(uri: "/api/v1/meta", method: .get))
            XCTAssertEqual(meta.categories.map(\.value), ClosetCore.Category.allCases.map(\.rawValue))
            XCTAssertEqual(meta.categories.first { $0.value == "socks" }?.displayName, "袜子")
            XCTAssertEqual(meta.categories.first { $0.value == "top" }?.subtypes.count, 8)
            XCTAssertEqual(meta.scenarios.first { $0.value == "formal" }?.conflictsWith, ["sport"])
            XCTAssertEqual(meta.warmthLevels.first { $0.value == "hot" }?.torsoBudget, 22)
            XCTAssertEqual(meta.warmthLevels.map { "\($0.minScore)-\($0.maxScore)" }, ["85-100", "68-84", "51-67", "34-50", "17-33", "1-16"])
            XCTAssertEqual(meta.rules.laundryRetentionWarningDays, 4)
            XCTAssertEqual(meta.rules.unwornDays, 90)
        }
    }

    // MARK: - 单品

    func testListItemsWithFilters() async throws {
        try await app().test(.router) { client in
            let all = try Self.decode(APIList<APIItem>.self, try await client.execute(uri: "/api/v1/items", method: .get))
            XCTAssertEqual(all.items.map(\.subtype), ["boots", "jeans", "tee"], "newest first")
            let laundry = try Self.decode(APIList<APIItem>.self, try await client.execute(uri: "/api/v1/items?status=inLaundry", method: .get))
            XCTAssertEqual(laundry.items.map(\.id.uuidString), [Self.jeansID])
            XCTAssertEqual(laundry.items.first?.title, "下装", "empty name falls back to category")
            let shoes = try Self.decode(APIList<APIItem>.self, try await client.execute(uri: "/api/v1/items?category=shoes", method: .get))
            XCTAssertEqual(shoes.items.count, 1)
            let bad = try await client.execute(uri: "/api/v1/items?status=lost", method: .get)
            XCTAssertEqual(bad.status, .badRequest)
            XCTAssertEqual(try Self.errorCode(bad), "invalid_parameter")
        }
    }

    func testItemDetail() async throws {
        try await app().test(.router) { client in
            let item = try Self.decode(APIItem.self, try await client.execute(uri: "/api/v1/items/\(Self.teeID)", method: .get))
            XCTAssertEqual(item.name, "白色T恤")
            XCTAssertEqual(item.scenarios, ["work", "casual"])
            XCTAssertEqual(item.warmthLevel, "warm")
            XCTAssertEqual(item.dominantColor.name, "白色")
            XCTAssertEqual(item.dominantColor.hex, "#F5F5F5")
            XCTAssertEqual(item.images.display?.format, "png")
            XCTAssertEqual(item.images.display?.displayable, true)
            XCTAssertEqual(item.images.original?.format, "jpeg")
            let lower = try await client.execute(uri: "/api/v1/items/\(Self.teeID.lowercased())", method: .get)
            XCTAssertEqual(lower.status, .ok, "UUIDs are case-insensitive")
            let invalid = try await client.execute(uri: "/api/v1/items/not-a-uuid", method: .get)
            XCTAssertEqual(invalid.status, .badRequest)
            let missing = try await client.execute(uri: "/api/v1/items/\(UUID().uuidString)", method: .get)
            XCTAssertEqual(missing.status, .notFound)
            XCTAssertEqual(try Self.errorCode(missing), "not_found")
        }
    }

    func testImageServingCachingAndVariants() async throws {
        try await app().test(.router) { client in
            let item = try Self.decode(APIItem.self, try await client.execute(uri: "/api/v1/items/\(Self.teeID)", method: .get))
            let url = try XCTUnwrap(item.images.display?.url)
            let image = try await client.execute(uri: url, method: .get)
            XCTAssertEqual(image.status, .ok)
            XCTAssertEqual(image.headers[.contentType], "image/png")
            XCTAssertEqual(image.headers[.cacheControl], "private, max-age=31536000, immutable")
            XCTAssertEqual(Array(image.body.readableBytesView.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
            let etag = try XCTUnwrap(image.headers[.eTag])

            let plain = try await client.execute(uri: "/api/v1/items/\(Self.teeID)/image", method: .get)
            XCTAssertEqual(plain.headers[.cacheControl], "no-cache")
            let revalidated = try await client.execute(uri: "/api/v1/items/\(Self.teeID)/image", method: .get, headers: [.ifNoneMatch: etag])
            XCTAssertEqual(revalidated.status, .notModified)
            XCTAssertEqual(revalidated.body.readableBytes, 0)

            let original = try await client.execute(uri: "/api/v1/items/\(Self.teeID)/image?variant=original", method: .get)
            XCTAssertEqual(original.headers[.contentType], "image/jpeg")
            let badVariant = try await client.execute(uri: "/api/v1/items/\(Self.teeID)/image?variant=thumb", method: .get)
            XCTAssertEqual(badVariant.status, .badRequest)
            let noImage = try await client.execute(uri: "/api/v1/items/\(Self.jeansID)/image", method: .get)
            XCTAssertEqual(noImage.status, .notFound)
        }
    }

    func testUnknownImageDataIsServedAsAttachment() async throws {
        let id = UUID()
        let dto = WardrobeBackup.ItemDTO(
            id: id, name: "x", category: "top", subtype: nil, scenarios: [], status: "inWardrobe", isWaterproof: false,
            laundryEntryDate: nil, dominantColor: StoredColor(red: 0, green: 0, blue: 0), secondaryColor: nil, warmthScore: 50,
            warmthLevels: [], seasons: [], brand: nil, notes: nil, createdAt: .now, updatedAt: .now,
            processedImageBase64: nil, originalImageBase64: Data("<svg onload=alert(1)>".utf8).base64EncodedString())
        _ = try await BackupImporter(store: store).importBackup(
            try WardrobeBackup.makeEncoder().encode(WardrobeBackup.Bundle(items: [dto], outfits: [], wearRecords: [])), mode: .merge, dryRun: false)
        try await app().test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/items/\(id.uuidString)/image", method: .get)
            XCTAssertEqual(response.headers[.contentType], "application/octet-stream", String(decoding: Data(response.body.readableBytesView), as: UTF8.self))
            XCTAssertTrue(response.headers[.contentDisposition]?.hasPrefix("attachment") ?? false)
            XCTAssertEqual(response.headers[HTTPField.Name("X-Content-Type-Options")!], "nosniff")
        }
    }

    // MARK: - 穿搭与记录

    func testOutfitsAndWearRecords() async throws {
        try await app().test(.router) { client in
            let favorites = try Self.decode(APIList<APIOutfit>.self, try await client.execute(uri: "/api/v1/outfits?favorite=true", method: .get))
            XCTAssertEqual(favorites.items.count, 1)
            XCTAssertEqual(favorites.items[0].members.map(\.item.subtype), ["tee", "jeans", "boots"])
            XCTAssertEqual(favorites.items[0].missingRequiredCategories, [])
            XCTAssertNil(favorites.items[0].members[0].slot, "imported outfits have no slot information")
            let bad = try await client.execute(uri: "/api/v1/outfits?favorite=yes", method: .get)
            XCTAssertEqual(bad.status, .badRequest)

            let records = try Self.decode(APIList<APIWearRecord>.self, try await client.execute(uri: "/api/v1/wear-records", method: .get))
            XCTAssertEqual(records.items.map(\.isActive), [true, false])
            XCTAssertEqual(records.items[1].items.count, 3)
            let active = try Self.decode(APIActiveWearRecord.self, try await client.execute(uri: "/api/v1/wear-records/active", method: .get))
            XCTAssertEqual(active.record?.notes, "只穿了上衣")
        }
    }

    func testMissingRequiredCategoriesAfterItemDeletion() async throws {
        try await store.transaction { _ = try $0.db.run("DELETE FROM items WHERE id = ?;", [.text(Self.jeansID)]) }
        try await app().test(.router) { client in
            let favorites = try Self.decode(APIList<APIOutfit>.self, try await client.execute(uri: "/api/v1/outfits?favorite=true", method: .get))
            XCTAssertEqual(favorites.items[0].missingRequiredCategories, ["bottom"])
        }
    }

    // MARK: - 安全

    func testUnknownRouteGetsJSONErrorAndHeaders() async throws {
        try await app().test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/nope", method: .get)
            XCTAssertEqual(response.status, .notFound)
            XCTAssertEqual(try Self.errorCode(response), "not_found")
            XCTAssertNotNil(response.headers[.contentSecurityPolicy])
        }
    }

    func testForeignHostIsRejected() async throws {
        // 路由测试框架固定使用 authority "localhost"；把它移出允许列表即可模拟外部域名。
        try await app(policy: LoopbackPolicy(port: 8765, allowedHosts: ["127.0.0.1"])).test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/health", method: .get)
            XCTAssertEqual(response.status, .forbidden)
            XCTAssertEqual(try Self.errorCode(response), "host_not_allowed")
        }
    }

    func testWriteRequestsNeedClientHeaderAndSameOrigin() async throws {
        let client = RequestGuardMiddleware<BasicRequestContext>.clientHeader
        try await app().test(.router) { http in
            let bare = try await http.execute(uri: "/api/v1/items", method: .post)
            XCTAssertEqual(bare.status, .forbidden)
            XCTAssertEqual(try Self.errorCode(bare), "request_rejected")
            let foreign = try await http.execute(uri: "/api/v1/items", method: .post,
                                                 headers: [client: "web", HTTPField.Name("Origin")!: "http://evil.example"])
            XCTAssertEqual(foreign.status, .forbidden)
            let otherPort = try await http.execute(uri: "/api/v1/items", method: .post,
                                                   headers: [client: "web", HTTPField.Name("Origin")!: "http://localhost:3000"])
            XCTAssertEqual(otherPort.status, .forbidden)
            let crossSite = try await http.execute(uri: "/api/v1/items", method: .post,
                                                   headers: [client: "web", HTTPField.Name("Sec-Fetch-Site")!: "cross-site"])
            XCTAssertEqual(crossSite.status, .forbidden)
            let sameOrigin = try await http.execute(uri: "/api/v1/items", method: .post,
                                                    headers: [client: "web", HTTPField.Name("Origin")!: "http://127.0.0.1:8765",
                                                              HTTPField.Name("Sec-Fetch-Site")!: "same-origin"])
            XCTAssertEqual(sameOrigin.status, .badRequest, "passes the guard and reaches item creation, which rejects the empty body")
        }
    }

    func testLoopbackPolicyParsing() {
        let policy = LoopbackPolicy(port: 8765)
        XCTAssertEqual(LoopbackPolicy.hostname(fromAuthority: "127.0.0.1:8765"), "127.0.0.1")
        XCTAssertEqual(LoopbackPolicy.hostname(fromAuthority: "[::1]:8765"), "::1")
        XCTAssertEqual(LoopbackPolicy.hostname(fromAuthority: "LocalHost"), "localhost")
        XCTAssertTrue(policy.isAllowedAuthority("localhost:8765"))
        XCTAssertTrue(policy.isAllowedAuthority("[::1]:8765"))
        XCTAssertFalse(policy.isAllowedAuthority("evil.example:8765"))
        XCTAssertFalse(policy.isAllowedAuthority("localhost.evil.example"))
        XCTAssertFalse(policy.isAllowedAuthority(nil))
        XCTAssertFalse(policy.isAllowedAuthority(""))
        XCTAssertTrue(policy.isAllowedOrigin("http://127.0.0.1:8765"))
        XCTAssertTrue(policy.isAllowedOrigin("http://[::1]:8765"))
        XCTAssertFalse(policy.isAllowedOrigin("http://127.0.0.1:9999"))
        XCTAssertFalse(policy.isAllowedOrigin("https://127.0.0.1:8765"))
        XCTAssertFalse(policy.isAllowedOrigin("null"))
    }
}
