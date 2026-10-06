import Foundation
import ClosetCore

/// 指向一份已存储图片的引用（按内容哈希寻址）。
public struct MediaRef: Sendable, Equatable, Hashable, Codable {
    public let sha256: String
    public let format: ImageFormat
    public let byteCount: Int

    public init(sha256: String, format: ImageFormat, byteCount: Int) {
        self.sha256 = sha256
        self.format = format
        self.byteCount = byteCount
    }
}

/// 数据库中的一件单品。字段含义与 App 的 `ClothingItem` 一一对应。
public struct StoredItem: WardrobeItemRepresentable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var category: ClosetCore.Category
    public var subtype: Subtype?
    public var scenarios: [Scenario]
    public var status: ItemStatus
    public var isWaterproof: Bool
    public var laundryEntryDate: Date?
    public var dominantColor: StoredColor
    public var secondaryColor: StoredColor?
    public var dominantColorCategory: ColorCategory
    public var warmthScore: Int
    public var warmthLevels: [WarmthLevel]
    public var seasons: [Season]
    public var brand: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var processedImage: MediaRef?
    public var originalImage: MediaRef?

    public init(
        id: UUID, name: String, category: ClosetCore.Category, subtype: Subtype?, scenarios: [Scenario],
        status: ItemStatus, isWaterproof: Bool, laundryEntryDate: Date?, dominantColor: StoredColor,
        secondaryColor: StoredColor?, dominantColorCategory: ColorCategory, warmthScore: Int,
        warmthLevels: [WarmthLevel], seasons: [Season], brand: String?, notes: String?,
        createdAt: Date, updatedAt: Date, processedImage: MediaRef?, originalImage: MediaRef?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.subtype = subtype
        self.scenarios = scenarios
        self.status = status
        self.isWaterproof = isWaterproof
        self.laundryEntryDate = laundryEntryDate
        self.dominantColor = dominantColor
        self.secondaryColor = secondaryColor
        self.dominantColorCategory = dominantColorCategory
        self.warmthScore = warmthScore
        self.warmthLevels = warmthLevels
        self.seasons = seasons
        self.brand = brand
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.processedImage = processedImage
        self.originalImage = originalImage
    }

    /// 展示用图片：优先去背结果，回退原图（与 App 的 `ItemCard` 相同）。
    public var displayImage: MediaRef? { processedImage ?? originalImage }
}

/// 穿搭中单品所在的槽位。导入自 iOS 备份的数据没有槽位信息，值为 nil。
public enum OutfitSlot: String, Codable, Sendable, CaseIterable {
    case outerwear, midLayer, top, bottom, socks, shoes, accessory
}

/// 穿搭或穿着记录中的一个成员。
public struct SlottedItemID: Sendable, Equatable, Codable {
    public var itemID: UUID
    public var slot: OutfitSlot?

    public init(itemID: UUID, slot: OutfitSlot? = nil) {
        self.itemID = itemID
        self.slot = slot
    }
}

/// 数据库中的一套穿搭。
public struct StoredOutfit: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var isFavorite: Bool
    public var source: OutfitSource
    public var targetScenario: Scenario?
    public var targetWarmthLevel: WarmthLevel?
    /// 成员按保存时的顺序排列。
    public var members: [SlottedItemID]
    public var canvasLayout: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, name: String, isFavorite: Bool, source: OutfitSource, targetScenario: Scenario?,
        targetWarmthLevel: WarmthLevel?, members: [SlottedItemID], canvasLayout: Data? = nil,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.source = source
        self.targetScenario = targetScenario
        self.targetWarmthLevel = targetWarmthLevel
        self.members = members
        self.canvasLayout = canvasLayout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var itemIDs: [UUID] { members.map(\.itemID) }
}

/// 数据库中的一条穿着记录。
public struct StoredWearRecord: Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var isActive: Bool
    public var outfitID: UUID?
    public var members: [SlottedItemID]
    public var notes: String?
    public var createdAt: Date

    public init(id: UUID, date: Date, isActive: Bool, outfitID: UUID?, members: [SlottedItemID], notes: String?, createdAt: Date) {
        self.id = id
        self.date = date
        self.isActive = isActive
        self.outfitID = outfitID
        self.members = members
        self.notes = notes
        self.createdAt = createdAt
    }

    public var itemIDs: [UUID] { members.map(\.itemID) }
}
