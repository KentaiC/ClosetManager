import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetCore
@testable import ClosetStorage
import ClosetServices
@testable import ClosetHTTP

/// 代替 macOS 图像框架的替身：抠图返回固定 PNG，派生图返回固定 JPEG。
struct ConvertingProcessor: ImageProcessor {
    var groups: [[UUID]] = []
    var capabilities: ImageCapabilities {
        ImageCapabilities(backgroundRemoval: true, colorExtraction: true, formatConversion: true, similarityDetection: true)
    }
    func removeBackground(from data: Data) async throws -> Data { ImageAPITests.png(width: 7, height: 9) }
    func extractColors(from data: Data) async -> (dominant: StoredColor, secondary: StoredColor?)? {
        (StoredColor(red: 1, green: 0, blue: 0), StoredColor(red: 0, green: 0, blue: 1))
    }
    func makeDerivedImage(from data: Data, maxPixelSize: Int) async -> Data? { ImageAPITests.jpeg }
    func similarGroups(_ inputs: [SimilarityInput]) async -> [[UUID]] { groups }
}

final class ImageAPITests: XCTestCase {
    static func png(width: UInt8, height: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
              0, 0, 0, width, 0, 0, 0, height, 8, 6, 0, 0, 0, 0, 0, 0, 0])
    }
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xC0, 0, 8, 8, 0, 4, 0, 6, 3, 0xFF, 0xD9])
    static let heic: Data = {
        func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { be32(8 + payload.count) + Array(type.utf8) + payload }
        let ispe = box("ispe", [0, 0, 0, 0] + be32(4032) + be32(3024))
        let meta = box("meta", [0, 0, 0, 0] + box("iprp", box("ipco", ispe)))
        return Data(box("ftyp", Array("heic".utf8) + [0, 0, 0, 0]) + meta)
    }()

    static let writeHeaders: HTTPFields = [RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web"]
    static let jsonHeaders: HTTPFields = [RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web", .contentType: "application/json"]
    static let now = Date(timeIntervalSince1970: 1_791_331_200)

    var store: ClosetStore!

    override func setUp() async throws {
        store = try ClosetStore(inMemoryWithMediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)"))
    }

    func app(_ processor: any ImageProcessor = UnavailableImageProcessor()) -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765), processor: processor, now: { Self.now }))
    }

    static func object(_ response: TestResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    }

    static func errorCode(_ response: TestResponse) throws -> String {
        ((try object(response)["error"] as? [String: Any])?["code"] as? String) ?? ""
    }

    static func itemBody(original: String, processed: String? = nil, extra: String = "") -> String {
        """
        {"name":"","category":"top","subtype":"tee","scenarios":["casual"],"warmthScore":50,"seasons":[],"status":"inWardrobe",
         "isWaterproof":false,"brand":"","notes":"","dominantColor":{"red":0.9,"green":0.9,"blue":0.9},
         "images":{"original":"\(original)"\(processed.map { ",\"processed\":\"\($0)\"" } ?? "")\(extra)}}
        """
    }

    func testUploadPreviewAndCreateWithoutImageFrameworks() async throws {
        try await app().test(.router) { client in
            let health = try Self.object(try await client.execute(uri: "/api/v1/health", method: .get))
            XCTAssertEqual(health["capabilities"] as? [String: Bool],
                           ["backgroundRemoval": false, "colorExtraction": false, "formatConversion": false, "similarityDetection": false])

            let png = Self.png(width: 3, height: 2)
            let upload = try await client.execute(uri: "/api/v1/images", method: .post, headers: Self.writeHeaders, body: ByteBuffer(data: png))
            XCTAssertEqual(upload.status, .created)
            let uploaded = try Self.object(upload)
            let sha = try XCTUnwrap(uploaded["sha256"] as? String)
            XCTAssertEqual(uploaded["format"] as? String, "png")
            XCTAssertEqual(uploaded["width"] as? Int, 3)
            XCTAssertEqual(uploaded["height"] as? Int, 2)
            XCTAssertEqual(uploaded["displayable"] as? Bool, true)
            XCTAssertEqual(uploaded["url"] as? String, "/api/v1/images/\(sha)")

            let preview = try await client.execute(uri: "/api/v1/images/\(sha)?variant=thumbnail", method: .get)
            XCTAssertEqual(preview.status, .ok)
            XCTAssertEqual(Data(preview.body.readableBytesView), png, "no thumbnail support: the original is served")
            XCTAssertEqual(preview.headers[.contentType], "image/png")
            XCTAssertEqual(preview.headers[.cacheControl], "private, max-age=31536000, immutable")

            let processed = try Self.object(try await client.execute(uri: "/api/v1/images/\(sha)/process", method: .post, headers: Self.writeHeaders))
            XCTAssertNil(processed["processed"])
            XCTAssertNil(processed["dominantColor"])

            let create = try await client.execute(uri: "/api/v1/items", method: .post, headers: Self.jsonHeaders, body: ByteBuffer(string: Self.itemBody(original: sha)))
            XCTAssertEqual(create.status, .created)
            let item = try Self.object(create)
            XCTAssertEqual(item["name"] as? String, "白色T恤")
            let images = try XCTUnwrap(item["images"] as? [String: Any])
            let thumbnail = try XCTUnwrap(images["thumbnailUrl"] as? String)
            let thumb = try await client.execute(uri: thumbnail, method: .get)
            XCTAssertEqual(Data(thumb.body.readableBytesView), png)

            let similar = try await client.execute(uri: "/api/v1/similar-items", method: .get)
            XCTAssertEqual(similar.status, .conflict)
        }
    }

    func testUploadIsGuardedAndValidated() async throws {
        let store = self.store!
        try await app().test(.router) { client in
            let unguarded = try await client.execute(uri: "/api/v1/images", method: .post, body: ByteBuffer(data: Self.png(width: 1, height: 1)))
            XCTAssertEqual(unguarded.status, .forbidden)

            let svg = try await client.execute(uri: "/api/v1/images", method: .post, headers: Self.writeHeaders,
                                               body: ByteBuffer(string: "<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"/>"))
            XCTAssertEqual(svg.status, .badRequest)
            XCTAssertEqual(try Self.errorCode(svg), "invalid_request")

            var huge = Self.png(width: 1, height: 1)
            huge.append(Data(count: ImageService.maxUploadBytes))
            let tooLarge = try await client.execute(uri: "/api/v1/images", method: .post, headers: Self.writeHeaders, body: ByteBuffer(data: huge))
            XCTAssertEqual(tooLarge.status, .contentTooLarge)
            XCTAssertEqual(try Self.errorCode(tooLarge), "payload_too_large")

            for path in ["/api/v1/images/..%2F..%2Fetc%2Fpasswd", "/api/v1/images/\(String(repeating: "a", count: 64))"] {
                let missing = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(missing.status, .notFound, path)
            }

            let noImage = try await client.execute(uri: "/api/v1/items", method: .post, headers: Self.jsonHeaders,
                                                   body: ByteBuffer(string: Self.itemBody(original: String(repeating: "d", count: 64))))
            XCTAssertEqual(noImage.status, .badRequest)
            let count = try await store.read { try $0.counts().items }
            XCTAssertEqual(count, 0)
        }
    }

    func testProcessingConversionAndImageReplacementOnMacOS() async throws {
        try await app(ConvertingProcessor()).test(.router) { client in
            let upload = try Self.object(try await client.execute(uri: "/api/v1/images", method: .post, headers: Self.writeHeaders, body: ByteBuffer(data: Self.heic)))
            let sha = try XCTUnwrap(upload["sha256"] as? String)
            XCTAssertEqual(upload["format"] as? String, "heic")
            XCTAssertEqual(upload["displayable"] as? Bool, true, "HEIC is converted before it is served")
            let preview = try await client.execute(uri: "/api/v1/images/\(sha)", method: .get)
            XCTAssertEqual(preview.headers[.contentType], "image/jpeg")

            let result = try Self.object(try await client.execute(uri: "/api/v1/images/\(sha)/process", method: .post, headers: Self.writeHeaders))
            let processed = try XCTUnwrap(result["processed"] as? [String: Any])
            let processedSHA = try XCTUnwrap(processed["sha256"] as? String)
            XCTAssertEqual(processed["format"] as? String, "png")
            XCTAssertEqual((result["dominantColor"] as? [String: Any])?["hex"] as? String, "#FF0000")
            XCTAssertEqual((result["secondaryColor"] as? [String: Any])?["hex"] as? String, "#0000FF")

            let create = try Self.object(try await client.execute(uri: "/api/v1/items", method: .post, headers: Self.jsonHeaders, body: ByteBuffer(string:
                Self.itemBody(original: sha, processed: processedSHA, extra: ",\"secondaryColor\":{\"red\":0,\"green\":0,\"blue\":1}"))))
            let id = try XCTUnwrap(create["id"] as? String)
            XCTAssertEqual((create["secondaryColor"] as? [String: Any])?["hex"] as? String, "#0000FF")
            let images = try XCTUnwrap(create["images"] as? [String: Any])
            XCTAssertEqual((images["display"] as? [String: Any])?["format"] as? String, "png")
            XCTAssertEqual((images["original"] as? [String: Any])?["displayable"] as? Bool, true)
            let original = try await client.execute(uri: "/api/v1/items/\(id)/image?variant=original", method: .get)
            XCTAssertEqual(Data(original.body.readableBytesView), Self.heic, "the original variant returns the stored bytes")
            let thumbnail = try await client.execute(uri: "/api/v1/items/\(id)/image?variant=thumbnail", method: .get)
            XCTAssertEqual(Data(thumbnail.body.readableBytesView), Self.jpeg)

            // 编辑时更换图片：提交新的原图，抠图结果与辅色一并替换。
            let replacement = try Self.object(try await client.execute(uri: "/api/v1/images", method: .post, headers: Self.writeHeaders,
                                                                        body: ByteBuffer(data: Self.png(width: 5, height: 5))))
            let newSHA = try XCTUnwrap(replacement["sha256"] as? String)
            let update = try await client.execute(uri: "/api/v1/items/\(id)", method: .put, headers: Self.jsonHeaders,
                                                  body: ByteBuffer(string: Self.itemBody(original: newSHA)))
            XCTAssertEqual(update.status, .ok)
            let updated = try Self.object(update)
            let updatedImages = try XCTUnwrap(updated["images"] as? [String: Any])
            XCTAssertNil(updatedImages["processed"])
            XCTAssertEqual((updatedImages["original"] as? [String: Any])?["format"] as? String, "png")
            XCTAssertNil(updated["secondaryColor"])
        }
    }

    func testSimilarItemsReturnsGroupsOfItems() async throws {
        let a = UUID(), b = UUID()
        let color = StoredColor(red: 0.5, green: 0.5, blue: 0.5)
        for (id, created) in [(a, 2.0), (b, 1.0)] {
            let item = StoredItem(id: id, name: "灰色T恤", category: .top, subtype: .tee, scenarios: [], status: .inWardrobe, isWaterproof: false,
                                  laundryEntryDate: nil, dominantColor: color, secondaryColor: nil, dominantColorCategory: .gray, warmthScore: 20,
                                  warmthLevels: [.warm], seasons: [], brand: nil, notes: nil, createdAt: Date(timeIntervalSince1970: created),
                                  updatedAt: Date(timeIntervalSince1970: created), processedImage: nil, originalImage: nil)
            try await store.transaction { try $0.insertItem(item) }
        }
        try await app(ConvertingProcessor(groups: [[a, b]])).test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/similar-items", method: .get)
            XCTAssertEqual(response.status, .ok)
            let groups = try XCTUnwrap(try Self.object(response)["groups"] as? [[[String: Any]]])
            XCTAssertEqual(groups.map { $0.compactMap { $0["id"] as? String } }, [[a.uuidString, b.uuidString]])
        }
    }
}
