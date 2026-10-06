import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

// 写操作的请求体。字段名与响应模型一致，枚举以原始值传输，在这里统一转换并校验。

struct ColorBody: Decodable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double?

    var storedColor: StoredColor { StoredColor(red: red, green: green, blue: blue, alpha: alpha ?? 1) }
}

struct ItemUpdateBody: Decodable {
    var name: String?
    var category: String
    var subtype: String?
    var scenarios: [String]
    var warmthScore: Int
    var seasons: [String]
    var status: String
    var isWaterproof: Bool
    var brand: String?
    var notes: String?
    var dominantColor: ColorBody

    func edit() throws -> ItemEdit {
        ItemEdit(
            name: name ?? "",
            category: try parse(category, "category"),
            subtype: try parseOptional(subtype, "subtype"),
            scenarios: try scenarios.map { try parse($0, "scenarios") },
            warmthScore: warmthScore,
            seasons: try seasons.map { try parse($0, "seasons") },
            status: try parse(status, "status"),
            isWaterproof: isWaterproof,
            brand: brand,
            notes: notes,
            dominantColor: dominantColor.storedColor)
    }
}

struct MemberBody: Decodable {
    var itemId: UUID
    var slot: String?

    func member() throws -> SlottedItemID {
        SlottedItemID(itemID: itemId, slot: try parseOptional(slot, "slot"))
    }
}

struct WearBody: Decodable {
    var outfitId: UUID?
    var members: [MemberBody]
}

struct TakeOffBody: Decodable {
    var laundryItemIds: [UUID]
}

struct ItemIDsBody: Decodable {
    var itemIds: [UUID]
}

struct OutfitCreateBody: Decodable {
    var name: String?
    var isFavorite: Bool?
    var source: String
    var targetScenario: String?
    var targetWarmthLevel: String?
    var members: [MemberBody]
}

struct ProfileBody: Codable, ResponseEncodable {
    var heightCm: Double
    var weightKg: Double
    var age: Int
    var gender: String

    init(_ profile: Profile) {
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        age = profile.age
        gender = profile.gender
    }

    var profile: Profile { Profile(heightCm: heightCm, weightKg: weightKg, age: age, gender: gender) }
}

func parse<E: RawRepresentable>(_ raw: String, _ field: String) throws -> E where E.RawValue == String {
    guard let value = E(rawValue: raw) else { throw APIError(.badRequest, code: "invalid_request", message: "字段 \(field) 的值「\(raw)」无效。") }
    return value
}

func parseOptional<E: RawRepresentable>(_ raw: String?, _ field: String) throws -> E? where E.RawValue == String {
    guard let raw, !raw.isEmpty else { return nil }
    return try parse(raw, field) as E
}

// MARK: - 写操作相关的响应

struct APISuggestion: Codable, Sendable {
    var id: UUID
    var members: [APIOutfit.Member]
}

struct APISuggestions: Codable, Sendable, ResponseEncodable {
    var drafts: [APISuggestion]
    var missingRequired: [String]
}

struct APICount: Codable, Sendable, ResponseEncodable {
    var count: Int
}

struct APIDefaultName: Codable, Sendable, ResponseEncodable {
    var name: String
}

struct APIAnalytics: Codable, Sendable, ResponseEncodable {
    struct CategoryCount: Codable, Sendable { var category: String; var count: Int }
    struct ColorCount: Codable, Sendable { var colorCategory: String; var count: Int }
    struct DayCount: Codable, Sendable { var date: String; var count: Int }

    var inventory: [CategoryCount]
    var colorInventory: [ColorCount]
    var colorFrequency: [ColorCount]
    /// 按本机时区的自然日统计，日期格式为 yyyy-MM-dd，按日期升序。
    var dailyActivity: [DayCount]
}

struct APITravelPlan: Codable, Sendable, ResponseEncodable {
    var days: Int
    var underwearCount: Int
    var socksCount: Int
    var showsCapHint: Bool
    var packingCap: Int
    var suggestion: [APIItem]
    var missingRequired: [String]
}
