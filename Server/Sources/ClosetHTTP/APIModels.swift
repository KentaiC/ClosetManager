import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

// API 响应模型。字段名与取值同 App 的数据模型一致，枚举以原始值传输；
// 中文显示名等派生字段由共享核心计算，前端不重复实现这些规则。

public struct APIColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public var hex: String
    public var name: String

    init(_ color: StoredColor) {
        red = color.red
        green = color.green
        blue = color.blue
        alpha = color.alpha
        hex = color.hexString
        name = color.refinedColorName
    }
}

public struct APIImage: Codable, Sendable, Equatable {
    public var url: String
    public var format: String
    public var byteCount: Int
    /// 主流浏览器能否直接显示。HEIC 等格式需要服务端转码后才能显示。
    public var displayable: Bool

    init(itemID: UUID, variant: String, ref: MediaRef) {
        url = "/api/v1/items/\(itemID.uuidString)/image?variant=\(variant)&v=\(ref.sha256.prefix(16))"
        format = ref.format.rawValue
        byteCount = ref.byteCount
        displayable = ref.format.isBrowserDisplayable
    }
}

public struct APIItemImages: Codable, Sendable, Equatable {
    public var display: APIImage?
    public var processed: APIImage?
    public var original: APIImage?
}

public struct APIItem: Codable, Sendable, Equatable, ResponseEncodable {
    public var id: UUID
    public var name: String
    public var title: String
    public var category: String
    public var subtype: String?
    public var scenarios: [String]
    public var status: String
    public var isWaterproof: Bool
    public var laundryEntryDate: Date?
    /// 在洗衣袋中超过阈值，规则来自共享核心 `WardrobeRules`。
    public var laundryRetentionWarning: Bool
    public var dominantColor: APIColor
    public var secondaryColor: APIColor?
    public var dominantColorCategory: String
    public var warmthScore: Int
    public var warmthLevel: String
    public var warmthLevels: [String]
    public var seasons: [String]
    public var brand: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var images: APIItemImages

    public init(_ item: StoredItem, now: Date = Date()) {
        id = item.id
        name = item.name
        title = ItemDefaults.displayTitle(name: item.name, category: item.category)
        category = item.category.rawValue
        subtype = item.subtype?.rawValue
        scenarios = item.scenarios.map(\.rawValue)
        status = item.status.rawValue
        isWaterproof = item.isWaterproof
        laundryEntryDate = item.laundryEntryDate
        laundryRetentionWarning = item.status == .inLaundry
            && WardrobeRules.isLaundryRetentionWarning(entryDate: item.laundryEntryDate, now: now)
        dominantColor = APIColor(item.dominantColor)
        secondaryColor = item.secondaryColor.map(APIColor.init)
        dominantColorCategory = item.dominantColorCategory.rawValue
        warmthScore = item.warmthScore
        warmthLevel = WarmthLevel.from(score: item.warmthScore).rawValue
        warmthLevels = item.warmthLevels.map(\.rawValue)
        seasons = item.seasons.map(\.rawValue)
        brand = item.brand
        notes = item.notes
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        images = APIItemImages(
            display: item.displayImage.map { APIImage(itemID: item.id, variant: "display", ref: $0) },
            processed: item.processedImage.map { APIImage(itemID: item.id, variant: "processed", ref: $0) },
            original: item.originalImage.map { APIImage(itemID: item.id, variant: "original", ref: $0) })
    }
}

public struct APIOutfit: Codable, Sendable, ResponseEncodable {
    public struct Member: Codable, Sendable {
        public var slot: String?
        public var item: APIItem
    }

    public var id: UUID
    public var name: String
    public var isFavorite: Bool
    public var source: String
    public var targetScenario: String?
    public var targetWarmthLevel: String?
    public var members: [Member]
    /// 缺失的必选槽位（上装、下装、鞋子），单品被删除后可能出现。
    public var missingRequiredCategories: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ resolved: ResolvedOutfit) {
        let outfit = resolved.outfit
        id = outfit.id
        name = outfit.name
        isFavorite = outfit.isFavorite
        source = outfit.source.rawValue
        targetScenario = outfit.targetScenario?.rawValue
        targetWarmthLevel = outfit.targetWarmthLevel?.rawValue
        let slots = Dictionary(outfit.members.map { ($0.itemID, $0.slot) }, uniquingKeysWith: { first, _ in first })
        members = resolved.items.map { Member(slot: slots[$0.id]??.rawValue, item: APIItem($0)) }
        let present = Set(resolved.items.map(\.category))
        missingRequiredCategories = ClosetCore.Category.allCases.filter { $0.isRequiredInOutfit && !present.contains($0) }.map(\.rawValue)
        createdAt = outfit.createdAt
        updatedAt = outfit.updatedAt
    }
}

public struct APIWearRecord: Codable, Sendable, ResponseEncodable {
    public var id: UUID
    public var date: Date
    public var isActive: Bool
    public var outfitId: UUID?
    public var items: [APIItem]
    public var notes: String?
    public var createdAt: Date

    public init(_ resolved: ResolvedWearRecord) {
        id = resolved.record.id
        date = resolved.record.date
        isActive = resolved.record.isActive
        outfitId = resolved.record.outfitID
        items = resolved.items.map { APIItem($0) }
        notes = resolved.record.notes
        createdAt = resolved.record.createdAt
    }
}

public struct APIActiveWearRecord: Codable, Sendable, ResponseEncodable {
    public var record: APIWearRecord?
}

public struct APIList<Element: Codable & Sendable>: Codable, Sendable, ResponseEncodable {
    public var items: [Element]
}

public struct APIHealth: Codable, Sendable, ResponseEncodable {
    public struct Capabilities: Codable, Sendable {
        /// 本地抠图（需要 macOS 的 Vision）。
        public var backgroundRemoval: Bool
        /// 相似单品检测（需要 macOS 的 Vision）。
        public var similarityDetection: Bool

        public init(backgroundRemoval: Bool, similarityDetection: Bool) {
            self.backgroundRemoval = backgroundRemoval
            self.similarityDetection = similarityDetection
        }
    }

    public var status: String
    public var version: String
    public var schemaVersion: Int
    public var counts: StoreCounts
    public var capabilities: Capabilities
}
