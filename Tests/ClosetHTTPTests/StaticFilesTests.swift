import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetStorage
@testable import ClosetHTTP

final class StaticFilesTests: XCTestCase {
    var webRoot: URL!
    var store: ClosetStore!

    override func setUp() async throws {
        webRoot = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: webRoot.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("<!doctype html><title>Closet</title>".utf8).write(to: webRoot.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8).write(to: webRoot.appendingPathComponent("assets/index-abc123.js"))
        store = try ClosetStore(inMemoryWithMediaRoot: webRoot.appendingPathComponent("media"))
    }

    func app() -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765, webRoot: webRoot)))
    }

    static func body(_ response: TestResponse) -> String { String(decoding: Data(response.body.readableBytesView), as: UTF8.self) }

    func testServesIndexAndAssetsWithCachePolicy() async throws {
        try await app().test(.router) { client in
            let index = try await client.execute(uri: "/", method: .get)
            XCTAssertEqual(index.status, .ok)
            XCTAssertTrue(Self.body(index).contains("<title>Closet</title>"))
            XCTAssertEqual(index.headers[.cacheControl], "no-cache")
            XCTAssertNotNil(index.headers[.contentSecurityPolicy])

            let asset = try await client.execute(uri: "/assets/index-abc123.js", method: .get)
            XCTAssertEqual(asset.status, .ok)
            XCTAssertEqual(asset.headers[.cacheControl], "public, max-age=31536000, immutable")
            XCTAssertTrue(asset.headers[.contentType]?.contains("javascript") ?? false)
        }
    }

    func testDeepLinksFallBackToIndex() async throws {
        try await app().test(.router) { client in
            for path in ["/laundry", "/items/7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E", "/settings"] {
                let response = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(response.status, .ok, path)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                XCTAssertTrue(Self.body(response).contains("<title>Closet</title>"))
            }
        }
    }

    func testMissingFilesAndUnknownAPIPathsStay404() async throws {
        try await app().test(.router) { client in
            let missingAsset = try await client.execute(uri: "/assets/missing.js", method: .get)
            XCTAssertEqual(missingAsset.status, .notFound)
            let favicon = try await client.execute(uri: "/favicon.ico", method: .get)
            XCTAssertEqual(favicon.status, .notFound)
            let api = try await client.execute(uri: "/api/v1/does-not-exist", method: .get)
            XCTAssertEqual(api.status, .notFound)
            XCTAssertTrue(Self.body(api).contains("not_found"))
        }
    }

    func testPathTraversalIsRejected() async throws {
        try await app().test(.router) { client in
            for path in ["/../Package.swift", "/assets/../../etc/passwd", "/%2e%2e/%2e%2e/etc/passwd"] {
                let response = try await client.execute(uri: path, method: .get)
                let body = Self.body(response)
                // 只允许两种结果：拒绝请求，或者把规范化后的路径当作前端路由返回 index.html。
                XCTAssertTrue(response.status != .ok || body.contains("<title>Closet</title>"), path)
                XCTAssertFalse(body.contains("root:"), path)
                XCTAssertFalse(body.contains("PackageDescription"), path)
            }
        }
    }

    func testWithoutWebRootOnlyAPIIsServed() async throws {
        let apiOnly = Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765)))
        try await apiOnly.test(.router) { client in
            let response = try await client.execute(uri: "/laundry", method: .get)
            XCTAssertEqual(response.status, .notFound)
        }
    }
}
