import Foundation
import SwiftData

/// 导入模式：覆盖（清空后导入）或合并（按 id 跳过已存在）。
enum RestoreMode {
    case overwrite
    case merge
}

/// 本地数据冷备份：把数据库记录 + 图片打包为单个 JSON 文件（图片以 base64 内联）。
///
/// 设计：用 Sendable 的 Codable DTO 序列化，**不直接序列化 @Model**；导出为 `.wardrobe`（JSON）。
enum BackupService {

    // MARK: - DTO

    struct Bundle: Codable {
        var version = 1
        var items: [ItemDTO]
        var outfits: [OutfitDTO]
        var wearRecords: [WearRecordDTO]
    }

    struct ItemDTO: Codable {
        var id: UUID
        var name: String
        var category: String
        var subtype: String?
        var scenarios: [String]
        var status: String
        var isWaterproof: Bool
        var laundryEntryDate: Date?
        var dominantColor: StoredColor
        var secondaryColor: StoredColor?
        var warmthScore: Int
        var warmthLevels: [String]
        var seasons: [String]
        var brand: String?
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var processedImageBase64: String?
        var originalImageBase64: String?
    }

    struct OutfitDTO: Codable {
        var id: UUID
        var name: String
        var isFavorite: Bool
        var source: String
        var targetScenario: String?
        var targetWarmthLevel: String?
        var itemIDs: [UUID]
        var createdAt: Date
        var updatedAt: Date
    }

    struct WearRecordDTO: Codable {
        var id: UUID
        var date: Date
        var isActive: Bool
        var outfitID: UUID?
        var itemIDs: [UUID]
        var notes: String?
        var createdAt: Date
    }

    // MARK: - 导出

    /// 读取当前库构建备份包。
    static func makeBundle(in context: ModelContext) -> Bundle {
        let items = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let outfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<WearRecord>())) ?? []

        return Bundle(
            items: items.map { item in
                ItemDTO(
                    id: item.id, name: item.name,
                    category: item.category.rawValue,
                    subtype: item.subtype?.rawValue,
                    scenarios: item.scenarios.map(\.rawValue),
                    status: item.status.rawValue,
                    isWaterproof: item.isWaterproof,
                    laundryEntryDate: item.laundryEntryDate,
                    dominantColor: item.dominantColor,
                    secondaryColor: item.secondaryColor,
                    warmthScore: item.warmthScore,
                    warmthLevels: item.warmthLevels.map(\.rawValue),
                    seasons: item.seasons.map(\.rawValue),
                    brand: item.brand, notes: item.notes,
                    createdAt: item.createdAt, updatedAt: item.updatedAt,
                    processedImageBase64: item.processedImageData?.base64EncodedString(),
                    originalImageBase64: item.originalImageData?.base64EncodedString()
                )
            },
            outfits: outfits.map { outfit in
                OutfitDTO(
                    id: outfit.id, name: outfit.name, isFavorite: outfit.isFavorite,
                    source: outfit.source.rawValue,
                    targetScenario: outfit.targetScenario?.rawValue,
                    targetWarmthLevel: outfit.targetWarmthLevel?.rawValue,
                    itemIDs: outfit.items.map(\.id),
                    createdAt: outfit.createdAt, updatedAt: outfit.updatedAt
                )
            },
            wearRecords: records.map { record in
                WearRecordDTO(
                    id: record.id, date: record.date, isActive: record.isActive,
                    outfitID: record.outfit?.id,
                    itemIDs: record.items.map(\.id),
                    notes: record.notes, createdAt: record.createdAt
                )
            }
        )
    }

    /// 导出为临时 `.wardrobe` 文件，返回 URL 供 `ShareLink` 分享。
    static func exportFile(in context: ModelContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeBundle(in: context))

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClosetBackup-\(stamp).wardrobe")
        try data.write(to: url)
        return url
    }

    // MARK: - 导入

    /// 从备份文件导入。
    static func restore(from url: URL, mode: RestoreMode, in context: ModelContext) throws {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(Bundle.self, from: data)
        apply(bundle, mode: mode, in: context)
    }

    private static func apply(_ bundle: Bundle, mode: RestoreMode, in context: ModelContext) {
        if mode == .overwrite {
            for record in (try? context.fetch(FetchDescriptor<WearRecord>())) ?? [] { context.delete(record) }
            for outfit in (try? context.fetch(FetchDescriptor<Outfit>())) ?? [] { context.delete(outfit) }
            for item in (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? [] { context.delete(item) }
        }

        // 已存在的对象（合并模式下用于跳过与关系连接）。
        var itemMap: [UUID: ClothingItem] = [:]
        var outfitMap: [UUID: Outfit] = [:]
        if mode == .merge {
            for item in (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? [] { itemMap[item.id] = item }
            for outfit in (try? context.fetch(FetchDescriptor<Outfit>())) ?? [] { outfitMap[outfit.id] = outfit }
        }

        // 单品
        for dto in bundle.items {
            if mode == .merge, itemMap[dto.id] != nil { continue }
            let item = ClothingItem(
                id: dto.id, name: dto.name,
                category: Category(rawValue: dto.category) ?? .top,
                subtype: dto.subtype.flatMap(Subtype.init(rawValue:)),
                scenarios: dto.scenarios.compactMap(Scenario.init(rawValue:)),
                status: ItemStatus(rawValue: dto.status) ?? .inWardrobe,
                isWaterproof: dto.isWaterproof,
                laundryEntryDate: dto.laundryEntryDate,
                processedImageData: dto.processedImageBase64.flatMap { Data(base64Encoded: $0) },
                originalImageData: dto.originalImageBase64.flatMap { Data(base64Encoded: $0) },
                dominantColor: dto.dominantColor,
                secondaryColor: dto.secondaryColor,
                warmthScore: dto.warmthScore,
                warmthLevels: dto.warmthLevels.compactMap(WarmthLevel.init(rawValue:)),
                seasons: dto.seasons.compactMap(Season.init(rawValue:)),
                brand: dto.brand, notes: dto.notes,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt
            )
            context.insert(item)
            itemMap[item.id] = item
        }

        // 穿搭（重建 items 关系）
        for dto in bundle.outfits {
            if mode == .merge, outfitMap[dto.id] != nil { continue }
            let outfit = Outfit(
                id: dto.id, name: dto.name, isFavorite: dto.isFavorite,
                source: OutfitSource(rawValue: dto.source) ?? .generated,
                targetScenario: dto.targetScenario.flatMap(Scenario.init(rawValue:)),
                targetWarmthLevel: dto.targetWarmthLevel.flatMap(WarmthLevel.init(rawValue:)),
                items: dto.itemIDs.compactMap { itemMap[$0] },
                createdAt: dto.createdAt, updatedAt: dto.updatedAt
            )
            context.insert(outfit)
            outfitMap[outfit.id] = outfit
        }

        // 穿搭记录（重建 items / outfit 关系）
        let existingRecordIDs = Set((try? context.fetch(FetchDescriptor<WearRecord>()))?.map(\.id) ?? [])
        for dto in bundle.wearRecords {
            if mode == .merge, existingRecordIDs.contains(dto.id) { continue }
            let record = WearRecord(
                id: dto.id, date: dto.date, isActive: dto.isActive,
                outfit: dto.outfitID.flatMap { outfitMap[$0] },
                items: dto.itemIDs.compactMap { itemMap[$0] },
                notes: dto.notes, createdAt: dto.createdAt
            )
            context.insert(record)
        }
    }
}
