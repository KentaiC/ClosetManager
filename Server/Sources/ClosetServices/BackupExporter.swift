import Foundation
import ClosetCore
import ClosetStorage

/// `.wardrobe` 备份导出，文件格式与 App 的 `BackupService.exportFile` 相同（共享 `WardrobeBackup` 定义与编码器）。
///
/// 备份格式第 1 版没有槽位字段，Web 版记录的穿搭槽位不会写入备份；App 本身没有槽位。
public struct BackupExporter: Sendable {
    let store: ClosetStore

    public init(store: ClosetStore) {
        self.store = store
    }

    /// 读取当前数据构建备份包。图片按存储的字节以 base64 内联，与 App 相同。
    public func makeBundle() async throws -> WardrobeBackup.Bundle {
        let (items, outfits, records) = try await store.read { session in
            (try session.items(), try session.outfits(), try session.wearRecords())
        }
        let media = store.media
        func base64(_ ref: MediaRef?) throws -> String? {
            try ref.map { try media.read($0).base64EncodedString() }
        }
        return WardrobeBackup.Bundle(
            items: try items.map { item in
                WardrobeBackup.ItemDTO(
                    id: item.id, name: item.name, category: item.category.rawValue, subtype: item.subtype?.rawValue,
                    scenarios: item.scenarios.map(\.rawValue), status: item.status.rawValue, isWaterproof: item.isWaterproof,
                    laundryEntryDate: item.laundryEntryDate, dominantColor: item.dominantColor, secondaryColor: item.secondaryColor,
                    warmthScore: item.warmthScore, warmthLevels: item.warmthLevels.map(\.rawValue), seasons: item.seasons.map(\.rawValue),
                    brand: item.brand, notes: item.notes, createdAt: item.createdAt, updatedAt: item.updatedAt,
                    processedImageBase64: try base64(item.processedImage), originalImageBase64: try base64(item.originalImage))
            },
            outfits: outfits.map { outfit in
                WardrobeBackup.OutfitDTO(
                    id: outfit.id, name: outfit.name, isFavorite: outfit.isFavorite, source: outfit.source.rawValue,
                    targetScenario: outfit.targetScenario?.rawValue, targetWarmthLevel: outfit.targetWarmthLevel?.rawValue,
                    itemIDs: outfit.members.map(\.itemID), createdAt: outfit.createdAt, updatedAt: outfit.updatedAt)
            },
            wearRecords: records.map { record in
                WardrobeBackup.WearRecordDTO(
                    id: record.id, date: record.date, isActive: record.isActive, outfitID: record.outfitID,
                    itemIDs: record.members.map(\.itemID), notes: record.notes, createdAt: record.createdAt)
            })
    }

    /// 编码为 `.wardrobe` 文件内容。
    public func export() async throws -> Data {
        try WardrobeBackup.makeEncoder().encode(try await makeBundle())
    }

    /// 文件名与 App 相同：`ClosetBackup-<ISO8601 时间，冒号换成连字符>.wardrobe`。
    public static func fileName(at date: Date) -> String {
        "ClosetBackup-\(ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")).wardrobe"
    }
}

/// 经浏览器导入备份：先预检；确认写入且预检通过时，先把当前数据导出到数据目录，再导入。
public struct BackupRestoreService: Sendable {
    /// 导入前自动备份保留的份数。
    public static let keptSnapshots = 5

    let store: ClosetStore
    let now: @Sendable () -> Date

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// - Parameter apply: 为 false 时只预检。
    /// - Returns: 导入报告。预检有错误时不写入，报告中 `applied` 为 false。
    /// - Throws: 文件无法解析时抛出 `ImportError.unreadable`。
    public func restore(_ data: Data, mode: RestoreMode, apply: Bool) async throws -> ImportReport {
        let importer = BackupImporter(store: store)
        var report = try await importer.importBackup(data, mode: mode, dryRun: true)
        guard apply, report.canApply else { return report }
        let snapshot = try await saveSnapshot()
        do {
            report = try await importer.importBackup(data, mode: mode, dryRun: false)
        } catch ImportError.rejected(let rejected) {
            report = rejected
        }
        report.preImportBackup = snapshot
        return report
    }

    /// 把当前数据导出到 `backups/before-import`，只保留最近几份。没有数据或没有数据目录时不保存。
    /// - Returns: 保存的文件名。
    func saveSnapshot() async throws -> String? {
        guard let directory = store.directory?.beforeImportBackupsURL else { return nil }
        let counts = try await store.read { try $0.counts() }
        guard counts.items + counts.outfits + counts.wearRecords > 0 else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = BackupExporter.fileName(at: now())
        try await BackupExporter(store: store).export().write(to: directory.appendingPathComponent(name), options: .atomic)
        let existing = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("ClosetBackup-") && $0.hasSuffix(".wardrobe") }.sorted()
        for old in existing.dropLast(Self.keptSnapshots) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
        return name
    }
}
