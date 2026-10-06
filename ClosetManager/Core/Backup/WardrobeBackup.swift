import Foundation

/// 导入模式：覆盖（清空后导入）或合并（按 id 跳过已存在）。
public enum RestoreMode: String, Codable, CaseIterable, Sendable {
    case overwrite
    case merge
}

/// `.wardrobe` 冷备份的文件格式（JSON，图片以 base64 内联）。
///
/// 这里定义的结构体就是备份文件的契约：属性名即 JSON 键名，日期使用 ISO8601。
/// App 的 `BackupService` 与本地 Web 服务端的导入器都使用这一份定义，保证两边读写同一种文件。
/// 修改任何属性名都会让已有备份无法读取，契约由 `WardrobeBackupContractTests` 固定。
public enum WardrobeBackup {
    /// 当前写出的格式版本。
    public static let currentVersion = 1

    public struct Bundle: Codable, Sendable {
        public var version = 1
        public var items: [ItemDTO]
        public var outfits: [OutfitDTO]
        public var wearRecords: [WearRecordDTO]

        public init(version: Int = 1, items: [ItemDTO], outfits: [OutfitDTO], wearRecords: [WearRecordDTO]) {
            self.version = version
            self.items = items
            self.outfits = outfits
            self.wearRecords = wearRecords
        }
    }

    public struct ItemDTO: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var category: String
        public var subtype: String?
        public var scenarios: [String]
        public var status: String
        public var isWaterproof: Bool
        public var laundryEntryDate: Date?
        public var dominantColor: StoredColor
        public var secondaryColor: StoredColor?
        public var warmthScore: Int
        public var warmthLevels: [String]
        public var seasons: [String]
        public var brand: String?
        public var notes: String?
        public var createdAt: Date
        public var updatedAt: Date
        public var processedImageBase64: String?
        public var originalImageBase64: String?

        public init(
            id: UUID, name: String, category: String, subtype: String?, scenarios: [String], status: String,
            isWaterproof: Bool, laundryEntryDate: Date?, dominantColor: StoredColor, secondaryColor: StoredColor?,
            warmthScore: Int, warmthLevels: [String], seasons: [String], brand: String?, notes: String?,
            createdAt: Date, updatedAt: Date, processedImageBase64: String?, originalImageBase64: String?
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
            self.warmthScore = warmthScore
            self.warmthLevels = warmthLevels
            self.seasons = seasons
            self.brand = brand
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.processedImageBase64 = processedImageBase64
            self.originalImageBase64 = originalImageBase64
        }
    }

    public struct OutfitDTO: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var isFavorite: Bool
        public var source: String
        public var targetScenario: String?
        public var targetWarmthLevel: String?
        public var itemIDs: [UUID]
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID, name: String, isFavorite: Bool, source: String, targetScenario: String?,
            targetWarmthLevel: String?, itemIDs: [UUID], createdAt: Date, updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.isFavorite = isFavorite
            self.source = source
            self.targetScenario = targetScenario
            self.targetWarmthLevel = targetWarmthLevel
            self.itemIDs = itemIDs
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public struct WearRecordDTO: Codable, Sendable {
        public var id: UUID
        public var date: Date
        public var isActive: Bool
        public var outfitID: UUID?
        public var itemIDs: [UUID]
        public var notes: String?
        public var createdAt: Date

        public init(id: UUID, date: Date, isActive: Bool, outfitID: UUID?, itemIDs: [UUID], notes: String?, createdAt: Date) {
            self.id = id
            self.date = date
            self.isActive = isActive
            self.outfitID = outfitID
            self.itemIDs = itemIDs
            self.notes = notes
            self.createdAt = createdAt
        }
    }

    /// 与 App 导出时相同的编码器配置。
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// 与 App 导入时相同的解码器配置。
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
