import Foundation
import ClosetCore
import ClosetStorage

/// `.wardrobe` 备份导入。
///
/// 读取的文件格式与 App 的 `BackupService` 完全相同（共享 `WardrobeBackup` 定义）。
/// 覆盖与合并两种模式的语义与 App 一致：覆盖先清空再写入，合并按 id 跳过已存在的记录。
///
/// 与 App 的差异在于校验更严格：App 遇到无法识别的枚举值时会静默替换为默认值（审计 M-02），
/// 这里改为报告错误并拒绝导入，避免改变数据含义。可以自动修正且不改变含义的问题记为警告。
public struct BackupImporter: Sendable {
    let store: ClosetStore

    public init(store: ClosetStore) {
        self.store = store
    }

    /// 导入一份备份。
    /// - Parameter dryRun: 为 true 时只做预检，不写入数据。
    /// - Throws: 文件无法解析时抛出 `ImportError.unreadable`；预检有错误且不是预检模式时抛出 `ImportError.rejected`。
    public func importBackup(_ data: Data, mode: RestoreMode, dryRun: Bool) async throws -> ImportReport {
        let bundle: WardrobeBackup.Bundle
        do {
            bundle = try WardrobeBackup.makeDecoder().decode(WardrobeBackup.Bundle.self, from: data)
        } catch {
            throw ImportError.unreadable(String(describing: error))
        }

        let existing: ExistingIDs
        let hasActiveRecord: Bool
        if mode == .merge {
            (existing, hasActiveRecord) = try await store.read { session in
                (try session.existingIDs(), try session.activeWearRecord() != nil)
            }
        } else {
            existing = ExistingIDs()
            hasActiveRecord = false
        }

        var plan = Self.plan(bundle, mode: mode, dryRun: dryRun, existing: existing, existingActiveRecord: hasActiveRecord)
        guard plan.report.canApply else {
            if dryRun { return plan.report }
            throw ImportError.rejected(plan.report)
        }
        guard !dryRun else { return plan.report }

        // 先写图片文件（按内容寻址，可重复写入），再在一个事务中写数据库。
        for blob in plan.images {
            try store.media.write(blob)
        }
        let rows = plan.rows
        do {
            try await store.transaction { session in
                if mode == .overwrite { try session.deleteAllWardrobeData() }
                for item in rows.items { try session.insertItem(item) }
                for outfit in rows.outfits { try session.insertOutfit(outfit) }
                for record in rows.wearRecords { try session.insertWearRecord(record) }
            }
        } catch {
            _ = try? await store.collectUnreferencedMedia()
            throw error
        }
        try await store.collectUnreferencedMedia()
        plan.report.applied = true
        return plan.report
    }

    // MARK: - 计划

    struct Rows: Sendable {
        var items: [StoredItem] = []
        var outfits: [StoredOutfit] = []
        var wearRecords: [StoredWearRecord] = []
    }

    struct Plan {
        var report: ImportReport
        var rows = Rows()
        var images: [Data] = []
    }

    static func plan(
        _ bundle: WardrobeBackup.Bundle, mode: RestoreMode, dryRun: Bool,
        existing: ExistingIDs, existingActiveRecord: Bool
    ) -> Plan {
        var plan = Plan(report: ImportReport(mode: mode, dryRun: dryRun, backupVersion: bundle.version))
        guard bundle.version == WardrobeBackup.currentVersion else {
            plan.report.errors.append(ImportIssue(.unsupportedVersion,
                "备份文件版本为 \(bundle.version)，当前只支持版本 \(WardrobeBackup.currentVersion)。"))
            return plan
        }
        var report = plan.report
        var rows = Rows()
        var images: [Data] = []
        var imageHashes = Set<String>()

        func error(_ code: ImportIssue.Code, _ message: String, _ entity: String, _ id: UUID) {
            report.errors.append(ImportIssue(code, message, entity: entity, id: id.uuidString))
        }
        func warning(_ code: ImportIssue.Code, _ message: String, _ entity: String, _ id: UUID) {
            report.warnings.append(ImportIssue(code, message, entity: entity, id: id.uuidString))
        }
        func parse<E: RawRepresentable>(_ raw: String, _ field: String, _ entity: String, _ id: UUID) -> E? where E.RawValue == String {
            if let value = E(rawValue: raw) { return value }
            error(.invalidValue, "字段 \(field) 的值「\(raw)」无法识别。", entity, id)
            return nil
        }
        func parseAll<E: RawRepresentable>(_ raws: [String], _ field: String, _ entity: String, _ id: UUID) -> [E] where E.RawValue == String {
            raws.compactMap { parse($0, field, entity, id) }
        }

        // 单品
        report.items.inBackup = bundle.items.count
        var seenItems = Set<UUID>()
        var importedItemIDs = Set<UUID>()
        for dto in bundle.items {
            guard seenItems.insert(dto.id).inserted else {
                error(.duplicateID, "备份中出现重复的单品 id。", "item", dto.id)
                continue
            }
            if mode == .merge, existing.items.contains(dto.id) {
                report.items.skippedExisting += 1
                continue
            }
            let errorsBefore = report.errors.count
            let category: ClosetCore.Category? = parse(dto.category, "category", "item", dto.id)
            let status: ItemStatus? = parse(dto.status, "status", "item", dto.id)
            let subtype: Subtype? = dto.subtype.flatMap { parse($0, "subtype", "item", dto.id) }
            let scenarios: [Scenario] = parseAll(dto.scenarios, "scenarios", "item", dto.id)
            let levels: [WarmthLevel] = parseAll(dto.warmthLevels, "warmthLevels", "item", dto.id)
            let seasons: [Season] = parseAll(dto.seasons, "seasons", "item", dto.id)
            if let category, let subtype, subtype.category != category {
                error(.subtypeCategoryMismatch, "子类「\(subtype.rawValue)」不属于分类「\(category.rawValue)」。", "item", dto.id)
            }
            if !(1...100).contains(dto.warmthScore) {
                error(.warmthScoreOutOfRange, "保暖度 \(dto.warmthScore) 超出 1 到 100 的范围。", "item", dto.id)
            }
            var refs: [MediaRef?] = []
            for (field, base64) in [("processedImageBase64", dto.processedImageBase64), ("originalImageBase64", dto.originalImageBase64)] {
                guard let base64 else { refs.append(nil); continue }
                guard let data = Data(base64Encoded: base64) else {
                    error(.invalidImageData, "字段 \(field) 不是有效的 base64。", "item", dto.id)
                    refs.append(nil)
                    continue
                }
                let ref = MediaRef(sha256: MediaStore.sha256Hex(data), format: ImageFormat.detect(data), byteCount: data.count)
                if ref.format == .unknown {
                    warning(.unknownImageFormat, "字段 \(field) 的数据无法识别为图片，将按原样保存。", "item", dto.id)
                }
                if imageHashes.insert(ref.sha256).inserted {
                    images.append(data)
                    report.imageCount += 1
                    report.imageBytes += data.count
                }
                refs.append(ref)
            }
            guard report.errors.count == errorsBefore, let category, let status else { continue }

            if (status == .inLaundry) != (dto.laundryEntryDate != nil) {
                warning(.inconsistentLaundryState, "洗衣状态与入袋时间不一致，将按原样导入。", "item", dto.id)
            }
            if !levels.isEmpty, !levels.contains(WarmthLevel.from(score: dto.warmthScore)) {
                warning(.inconsistentWarmthLevels, "保暖标签与保暖度 \(dto.warmthScore) 不一致，将按原样导入。", "item", dto.id)
            }
            rows.items.append(StoredItem(
                id: dto.id, name: dto.name, category: category, subtype: subtype, scenarios: scenarios, status: status,
                isWaterproof: dto.isWaterproof, laundryEntryDate: dto.laundryEntryDate, dominantColor: dto.dominantColor,
                secondaryColor: dto.secondaryColor, dominantColorCategory: ColorCategory.classify(dto.dominantColor),
                warmthScore: dto.warmthScore, warmthLevels: ItemDefaults.resolvedWarmthLevels(levels, warmthScore: dto.warmthScore),
                seasons: seasons, brand: dto.brand, notes: dto.notes, createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                processedImage: refs[0], originalImage: refs[1]))
            importedItemIDs.insert(dto.id)
        }
        report.items.toImport = rows.items.count
        let availableItems = importedItemIDs.union(existing.items)

        func members(_ ids: [UUID], _ entity: String, _ owner: UUID) -> [SlottedItemID] {
            var seen = Set<UUID>()
            var result: [SlottedItemID] = []
            for id in ids {
                guard availableItems.contains(id) else {
                    warning(.missingItemReference, "引用的单品 \(id.uuidString) 不存在，已从成员中移除。", entity, owner)
                    continue
                }
                guard seen.insert(id).inserted else {
                    warning(.duplicateMember, "单品 \(id.uuidString) 重复出现，只保留一次。", entity, owner)
                    continue
                }
                result.append(SlottedItemID(itemID: id))
            }
            return result
        }

        // 穿搭
        report.outfits.inBackup = bundle.outfits.count
        var seenOutfits = Set<UUID>()
        var importedOutfitIDs = Set<UUID>()
        for dto in bundle.outfits {
            guard seenOutfits.insert(dto.id).inserted else {
                error(.duplicateID, "备份中出现重复的穿搭 id。", "outfit", dto.id)
                continue
            }
            if mode == .merge, existing.outfits.contains(dto.id) {
                report.outfits.skippedExisting += 1
                continue
            }
            let errorsBefore = report.errors.count
            let source: OutfitSource? = parse(dto.source, "source", "outfit", dto.id)
            let scenario: Scenario? = dto.targetScenario.flatMap { parse($0, "targetScenario", "outfit", dto.id) }
            let warmth: WarmthLevel? = dto.targetWarmthLevel.flatMap { parse($0, "targetWarmthLevel", "outfit", dto.id) }
            guard report.errors.count == errorsBefore, let source else { continue }
            rows.outfits.append(StoredOutfit(
                id: dto.id, name: dto.name, isFavorite: dto.isFavorite, source: source, targetScenario: scenario,
                targetWarmthLevel: warmth, members: members(dto.itemIDs, "outfit", dto.id),
                createdAt: dto.createdAt, updatedAt: dto.updatedAt))
            importedOutfitIDs.insert(dto.id)
        }
        report.outfits.toImport = rows.outfits.count
        let availableOutfits = importedOutfitIDs.union(existing.outfits)

        // 穿着记录
        report.wearRecords.inBackup = bundle.wearRecords.count
        var seenRecords = Set<UUID>()
        for dto in bundle.wearRecords {
            guard seenRecords.insert(dto.id).inserted else {
                error(.duplicateID, "备份中出现重复的穿着记录 id。", "wearRecord", dto.id)
                continue
            }
            if mode == .merge, existing.wearRecords.contains(dto.id) {
                report.wearRecords.skippedExisting += 1
                continue
            }
            var outfitID = dto.outfitID
            if let id = outfitID, !availableOutfits.contains(id) {
                warning(.missingOutfitReference, "引用的穿搭 \(id.uuidString) 不存在，记录将不关联穿搭。", "wearRecord", dto.id)
                outfitID = nil
            }
            rows.wearRecords.append(StoredWearRecord(
                id: dto.id, date: dto.date, isActive: dto.isActive, outfitID: outfitID,
                members: members(dto.itemIDs, "wearRecord", dto.id), notes: dto.notes, createdAt: dto.createdAt))
        }
        report.wearRecords.toImport = rows.wearRecords.count

        // 「目前正在穿」至多一条。
        let activeIndices = rows.wearRecords.indices.filter { rows.wearRecords[$0].isActive }
        if !activeIndices.isEmpty {
            if existingActiveRecord {
                for index in activeIndices {
                    rows.wearRecords[index].isActive = false
                    warning(.activeRecordConflict, "当前已有正在穿的记录，导入的这条记录将作为历史记录。", "wearRecord", rows.wearRecords[index].id)
                }
            } else if activeIndices.count > 1 {
                // 与 App 看板一致：按日期倒序取第一条作为正在穿。
                let keep = activeIndices.max { a, b in
                    let ra = rows.wearRecords[a], rb = rows.wearRecords[b]
                    return (ra.date, ra.createdAt, ra.id.uuidString) < (rb.date, rb.createdAt, rb.id.uuidString)
                }!
                for index in activeIndices where index != keep {
                    rows.wearRecords[index].isActive = false
                    warning(.multipleActiveRecords, "备份中有多条正在穿的记录，只保留日期最新的一条，这条将作为历史记录。", "wearRecord", rows.wearRecords[index].id)
                }
            }
        }

        plan.report = report
        plan.rows = rows
        plan.images = images
        return plan
    }
}
