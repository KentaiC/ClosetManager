import XCTest
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ClosetCore
@testable import ClosetStorage
import ClosetServices
@testable import ClosetHTTP

final class WriteAPITests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wardrobe-v1-sample.wardrobe")
    static let tee = "7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E"
    static let jeans = "8B3D2E0F-4C5A-4D6B-8E7F-2A3B4C5D6E7F"
    static let boots = "9C4E3F1A-5D6B-4E7C-9F8A-3B4C5D6E7F8A"
    static let activeRecord = "C3D4E5F6-A7B8-4C9D-8E0F-2A3B4C5D6E7F"
    static let outfit = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
    static let now = Date(timeIntervalSince1970: 1_791_331_200) // 2026-10-06

    var store: ClosetStore!

    override func setUp() async throws {
        store = try ClosetStore(inMemoryWithMediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString)"))
        _ = try await BackupImporter(store: store).importBackup(try Data(contentsOf: Self.fixture), mode: .overwrite, dryRun: false)
    }

    func app() -> some ApplicationProtocol {
        Application(router: makeRouter(store: store, configuration: ServerConfiguration(port: 8765), now: { Self.now }))
    }

    static let writeHeaders: HTTPFields = [RequestGuardMiddleware<BasicRequestContext>.clientHeader: "web", .contentType: "application/json"]

    static func body(_ json: String) -> ByteBuffer { ByteBuffer(string: json) }

    static func object(_ response: TestResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    }

    static func errorCode(_ response: TestResponse) throws -> String {
        ((try object(response)["error"] as? [String: Any])?["code"] as? String) ?? ""
    }

    static func errorMessage(_ response: TestResponse) throws -> String {
        ((try object(response)["error"] as? [String: Any])?["message"] as? String) ?? ""
    }

    func testEditItem() async throws {
        try await app().test(.router) { client in
            let update = """
            {"name":"","category":"bottom","subtype":"shorts","scenarios":["sport"],"warmthScore":10,"seasons":["summer"],
             "status":"inWardrobe","isWaterproof":false,"brand":"","notes":null,"dominantColor":{"red":0,"green":0.5,"blue":0}}
            """
            let response = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .put, headers: Self.writeHeaders, body: Self.body(update))
            XCTAssertEqual(response.status, .ok)
            let item = try Self.object(response)
            XCTAssertEqual(item["name"] as? String, "绿色短裤")
            XCTAssertEqual(item["warmthLevel"] as? String, "hot")
            XCTAssertEqual(item["dominantColorCategory"] as? String, "green")

            let blocked = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .put, headers: [.contentType: "application/json"], body: Self.body(update))
            XCTAssertEqual(blocked.status, .forbidden)

            let badEnum = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .put, headers: Self.writeHeaders,
                                                   body: Self.body(update.replacingOccurrences(of: "\"bottom\"", with: "\"hats\"")))
            XCTAssertEqual(badEnum.status, .badRequest)
            XCTAssertEqual(try Self.errorCode(badEnum), "invalid_request")

            let mismatch = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .put, headers: Self.writeHeaders,
                                                    body: Self.body(update.replacingOccurrences(of: "\"shorts\"", with: "\"tee\"")))
            XCTAssertEqual(mismatch.status, .badRequest)

            let malformed = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .put, headers: Self.writeHeaders, body: Self.body("{"))
            XCTAssertEqual(malformed.status, .badRequest)
            XCTAssertEqual(try Self.errorCode(malformed), "bad_request")

            let name = try await client.execute(uri: "/api/v1/naming/default-name?category=outerwear&subtype=overcoat&color=%23B59166", method: .get)
            XCTAssertEqual(try Self.object(name)["name"] as? String, "橙色大衣")
        }
    }

    func testWearTakeOffAndLaundryFlow() async throws {
        try await app().test(.router) { client in
            let rejected = try await client.execute(uri: "/api/v1/wear-records", method: .post, headers: Self.writeHeaders, body: Self.body("""
                {"members":[{"itemId":"\(Self.tee)","slot":"top"},{"itemId":"\(Self.boots)","slot":"shoes"}]}
                """))
            XCTAssertEqual(rejected.status, .conflict, "the boots are in the luggage (audit H-03)")
            XCTAssertEqual(try Self.errorMessage(rejected), "这套穿搭中有单品不在衣橱：防水靴在行李箱。请先放回衣橱再穿。")
            let stillActive = try Self.object(try await client.execute(uri: "/api/v1/wear-records/active", method: .get))
            XCTAssertEqual((stillActive["record"] as? [String: Any])?["id"] as? String, Self.activeRecord, "a rejected wear keeps the current record")
            _ = try await client.execute(uri: "/api/v1/travel/unpack-all", method: .post, headers: Self.writeHeaders)

            let wear = try await client.execute(uri: "/api/v1/wear-records", method: .post, headers: Self.writeHeaders, body: Self.body("""
                {"members":[{"itemId":"\(Self.tee)","slot":"top"},{"itemId":"\(Self.boots)","slot":"shoes"}]}
                """))
            XCTAssertEqual(wear.status, .ok)
            let record = try Self.object(wear)
            let recordID = try XCTUnwrap(record["id"] as? String)
            XCTAssertEqual(record["isActive"] as? Bool, true)

            let active = try Self.object(try await client.execute(uri: "/api/v1/wear-records/active", method: .get))
            XCTAssertEqual((active["record"] as? [String: Any])?["id"] as? String, recordID)
            let all = try Self.object(try await client.execute(uri: "/api/v1/wear-records", method: .get))
            XCTAssertEqual((all["items"] as? [[String: Any]])?.filter { $0["isActive"] as? Bool == true }.count, 1, "previous active record was closed")

            let takeOff = try await client.execute(uri: "/api/v1/wear-records/\(recordID)/take-off", method: .post, headers: Self.writeHeaders,
                                                   body: Self.body(#"{"laundryItemIds":["\#(Self.tee)"]}"#))
            XCTAssertEqual(takeOff.status, .ok)
            XCTAssertEqual(try Self.object(takeOff)["isActive"] as? Bool, false)
            let tee = try Self.object(try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .get))
            XCTAssertEqual(tee["status"] as? String, "inLaundry")
            XCTAssertEqual(tee["laundryRetentionWarning"] as? Bool, false, "just entered the laundry")
            let boots = try Self.object(try await client.execute(uri: "/api/v1/items/\(Self.boots)", method: .get))
            XCTAssertEqual(boots["status"] as? String, "inWardrobe", "unchecked wardrobe items stay in the wardrobe")

            let again = try await client.execute(uri: "/api/v1/wear-records/\(recordID)/take-off", method: .post, headers: Self.writeHeaders,
                                                 body: Self.body(#"{"laundryItemIds":[]}"#))
            XCTAssertEqual(again.status, .conflict)

            let laundry = try Self.object(try await client.execute(uri: "/api/v1/items?status=inLaundry&sort=updatedAt", method: .get))
            let laundryItems = try XCTUnwrap(laundry["items"] as? [[String: Any]])
            XCTAssertEqual(laundryItems.map { $0["id"] as? String }, [Self.tee, Self.jeans], "most recently updated first")
            XCTAssertEqual(laundryItems.last?["laundryRetentionWarning"] as? Bool, true, "jeans entered the laundry in July")

            let returned = try await client.execute(uri: "/api/v1/laundry/return", method: .post, headers: Self.writeHeaders,
                                                    body: Self.body(#"{"itemIds":["\#(Self.tee)","\#(Self.jeans)"]}"#))
            XCTAssertEqual(returned.status, .ok)
            let notInLaundry = try await client.execute(uri: "/api/v1/laundry/return", method: .post, headers: Self.writeHeaders,
                                                        body: Self.body(#"{"itemIds":["\#(Self.tee)"]}"#))
            XCTAssertEqual(notInLaundry.status, .conflict)
            XCTAssertEqual(try Self.errorCode(notInLaundry), "conflict")

            let deleted = try await client.execute(uri: "/api/v1/wear-records/\(recordID)", method: .delete, headers: Self.writeHeaders)
            XCTAssertEqual(deleted.status, .noContent)
        }
    }

    func testOutfitsSuggestionsAndFavorites() async throws {
        let store = try XCTUnwrap(store)
        try await app().test(.router) { client in
            let suggestions = try Self.object(try await client.execute(uri: "/api/v1/outfit-suggestions?warmth=mild&scenario=casual", method: .get))
            XCTAssertEqual(suggestions["missingRequired"] as? [String], ["bottom", "shoes"],
                           "the jeans have no scenario and the boots are in the luggage (audit H-01, kept as-is)")
            let invalid = try await client.execute(uri: "/api/v1/outfit-suggestions?warmth=boiling&scenario=casual", method: .get)
            XCTAssertEqual(invalid.status, .badRequest)

            let created = try await client.execute(uri: "/api/v1/outfits", method: .post, headers: Self.writeHeaders, body: Self.body("""
                {"source":"manual","members":[{"itemId":"\(Self.tee)","slot":"top"},{"itemId":"\(Self.jeans)","slot":"bottom"},{"itemId":"\(Self.boots)","slot":"shoes"}]}
                """))
            XCTAssertEqual(created.status, .ok)
            let outfit = try Self.object(created)
            let outfitID = try XCTUnwrap(outfit["id"] as? String)
            XCTAssertEqual(outfit["name"] as? String, "收藏穿搭")
            XCTAssertEqual(outfit["source"] as? String, "manual")
            XCTAssertEqual((outfit["members"] as? [[String: Any]])?.map { $0["slot"] as? String }, ["top", "bottom", "shoes"])

            let unavailable = try await client.execute(uri: "/api/v1/outfits/\(Self.outfit)/wear", method: .post, headers: Self.writeHeaders)
            XCTAssertEqual(unavailable.status, .conflict, "the favorite has the jeans in the laundry and the boots in the luggage (audit H-03)")
            XCTAssertEqual(try Self.errorMessage(unavailable), "这套穿搭中有单品不在衣橱：下装在洗衣袋，防水靴在行李箱。请先放回衣橱再穿。")
            try await store.transaction { s in _ = try s.db.run("UPDATE items SET status = 'inWardrobe', laundry_entry_at = NULL;") }
            let worn = try await client.execute(uri: "/api/v1/outfits/\(Self.outfit)/wear", method: .post, headers: Self.writeHeaders)
            XCTAssertEqual(try Self.object(worn)["outfitId"] as? String, Self.outfit)

            let removed = try await client.execute(uri: "/api/v1/outfits/\(outfitID)", method: .delete, headers: Self.writeHeaders)
            XCTAssertEqual(removed.status, .noContent)
            let missing = try await client.execute(uri: "/api/v1/outfits/\(outfitID)", method: .delete, headers: Self.writeHeaders)
            XCTAssertEqual(missing.status, .notFound)
        }
    }

    func testSuggestionsReturnSlottedDrafts() async throws {
        try await store.transaction { s in
            _ = try s.db.run("UPDATE items SET scenarios = '[\"casual\"]', status = 'inWardrobe';")
        }
        try await app().test(.router) { client in
            let response = try Self.object(try await client.execute(uri: "/api/v1/outfit-suggestions?warmth=cool&scenario=casual&maxCount=3", method: .get))
            let drafts = try XCTUnwrap(response["drafts"] as? [[String: Any]])
            XCTAssertFalse(drafts.isEmpty)
            let slots = (drafts[0]["members"] as? [[String: Any]])?.compactMap { $0["slot"] as? String }
            XCTAssertEqual(slots, ["top", "bottom", "shoes"])
        }
    }

    func testAnalyticsSearchTravelAndProfile() async throws {
        try await app().test(.router) { client in
            let analytics = try Self.object(try await client.execute(uri: "/api/v1/analytics", method: .get))
            XCTAssertEqual((analytics["inventory"] as? [[String: Any]])?.map { $0["category"] as? String }, ["top", "bottom", "shoes"])
            XCTAssertEqual((analytics["dailyActivity"] as? [[String: Any]])?.count, 2)
            XCTAssertEqual((analytics["dailyActivity"] as? [[String: Any]])?.first?["date"] as? String, "2026-06-24")

            let unworn = try Self.object(try await client.execute(uri: "/api/v1/search?unwornDays=90", method: .get))
            XCTAssertEqual((unworn["items"] as? [[String: Any]])?.count, 3, "last wear records are from June and July")
            let waterproof = try Self.object(try await client.execute(uri: "/api/v1/search?waterproof=true", method: .get))
            XCTAssertEqual((waterproof["items"] as? [[String: Any]])?.map { $0["id"] as? String }, [Self.boots])
            let badDays = try await client.execute(uri: "/api/v1/search?unwornDays=-1", method: .get)
            XCTAssertEqual(badDays.status, .badRequest)

            let plan = try Self.object(try await client.execute(uri: "/api/v1/travel/plan?days=3&warmth=mild&scenario=casual", method: .get))
            XCTAssertEqual(plan["underwearCount"] as? Int, 4)
            XCTAssertEqual(plan["showsCapHint"] as? Bool, false)
            XCTAssertEqual(plan["packingCap"] as? Int, 5)
            let packed = try await client.execute(uri: "/api/v1/travel/pack", method: .post, headers: Self.writeHeaders,
                                                  body: Self.body(#"{"itemIds":["\#(Self.tee)"]}"#))
            XCTAssertEqual(((try Self.object(packed)["items"]) as? [[String: Any]])?.first?["status"] as? String, "inLuggage")
            let unpacked = try Self.object(try await client.execute(uri: "/api/v1/travel/unpack-all", method: .post, headers: Self.writeHeaders))
            XCTAssertEqual(unpacked["count"] as? Int, 2, "the tee and the boots from the fixture")

            let profile = try Self.object(try await client.execute(uri: "/api/v1/settings/profile", method: .get))
            XCTAssertEqual(profile["gender"] as? String, "unspecified")
            let saved = try await client.execute(uri: "/api/v1/settings/profile", method: .put, headers: Self.writeHeaders,
                                                 body: Self.body(#"{"heightCm":170,"weightKg":55.5,"age":28,"gender":"female"}"#))
            XCTAssertEqual(try Self.object(saved)["age"] as? Int, 28)
            let invalid = try await client.execute(uri: "/api/v1/settings/profile", method: .put, headers: Self.writeHeaders,
                                                   body: Self.body(#"{"heightCm":170,"weightKg":55.5,"age":200,"gender":"female"}"#))
            XCTAssertEqual(invalid.status, .badRequest)
        }
    }

    func testDeleteItem() async throws {
        try await app().test(.router) { client in
            let deleted = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .delete, headers: Self.writeHeaders)
            XCTAssertEqual(deleted.status, .noContent)
            let gone = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .get)
            XCTAssertEqual(gone.status, .notFound)
            let again = try await client.execute(uri: "/api/v1/items/\(Self.tee)", method: .delete, headers: Self.writeHeaders)
            XCTAssertEqual(again.status, .notFound)
            let outfits = try Self.object(try await client.execute(uri: "/api/v1/outfits?favorite=true", method: .get))
            XCTAssertEqual(((outfits["items"] as? [[String: Any]])?.first?["missingRequiredCategories"]) as? [String], ["top"])
        }
    }
}
