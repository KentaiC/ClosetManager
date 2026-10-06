import Foundation
import ClosetCore

/// 单品查询条件。
public struct ItemFilter: Sendable {
    public enum Sort: String, Sendable {
        /// 录入时间倒序（衣橱网格）。
        case createdAt
        /// 更新时间倒序（洗衣房）。
        case updatedAt
    }

    public var status: ItemStatus?
    public var category: ClosetCore.Category?
    public var ids: [UUID]?
    public var sort: Sort

    public init(status: ItemStatus? = nil, category: ClosetCore.Category? = nil, ids: [UUID]? = nil, sort: Sort = .createdAt) {
        self.status = status
        self.category = category
        self.ids = ids
        self.sort = sort
    }
}

/// 各表记录数。
public struct StoreCounts: Sendable, Equatable, Codable {
    public var items: Int
    public var outfits: Int
    public var wearRecords: Int
    public var media: Int

    public init(items: Int, outfits: Int, wearRecords: Int, media: Int) {
        self.items = items
        self.outfits = outfits
        self.wearRecords = wearRecords
        self.media = media
    }
}

/// 已存在记录的 id 集合。
public struct ExistingIDs: Sendable {
    public var items: Set<UUID>
    public var outfits: Set<UUID>
    public var wearRecords: Set<UUID>

    public init(items: Set<UUID> = [], outfits: Set<UUID> = [], wearRecords: Set<UUID> = []) {
        self.items = items
        self.outfits = outfits
        self.wearRecords = wearRecords
    }
}

/// 一次数据库会话：只在 `ClosetStore.read` 或 `ClosetStore.transaction` 的闭包内有效。
public final class StoreSession {
    let db: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(db: SQLiteDatabase) {
        self.db = db
    }

    // MARK: - 单品

    private static let itemSelect = """
        SELECT i.*, pm.sha256 AS pm_sha, pm.format AS pm_format, pm.byte_count AS pm_bytes,
               om.sha256 AS om_sha, om.format AS om_format, om.byte_count AS om_bytes
        FROM items i
        LEFT JOIN media pm ON pm.sha256 = i.processed_media
        LEFT JOIN media om ON om.sha256 = i.original_media
        """

    /// 默认按录入时间倒序返回单品，与 App 衣橱网格的排序一致。
    public func items(_ filter: ItemFilter = ItemFilter()) throws -> [StoredItem] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        if let status = filter.status {
            clauses.append("i.status = ?")
            bindings.append(.text(status.rawValue))
        }
        if let category = filter.category {
            clauses.append("i.category = ?")
            bindings.append(.text(category.rawValue))
        }
        if let ids = filter.ids {
            if ids.isEmpty { return [] }
            clauses.append("i.id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")))")
            bindings.append(contentsOf: ids.map { .text($0.uuidString) })
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let order = filter.sort == .updatedAt ? "i.updated_at DESC, i.id" : "i.created_at DESC, i.id"
        return try db.query(Self.itemSelect + whereClause + " ORDER BY \(order);", bindings).map(decodeItem)
    }

    public func item(id: UUID) throws -> StoredItem? {
        try items(ItemFilter(ids: [id])).first
    }

    public func insertItem(_ item: StoredItem) throws {
        for ref in [item.processedImage, item.originalImage].compactMap({ $0 }) {
            try insertMedia(ref)
        }
        try db.run("""
            INSERT INTO items (
                id, name, category, subtype, scenarios, status, is_waterproof, laundry_entry_at,
                processed_media, original_media,
                dominant_red, dominant_green, dominant_blue, dominant_alpha,
                secondary_red, secondary_green, secondary_blue, secondary_alpha,
                dominant_color_category, warmth_score, warmth_levels, seasons, brand, notes, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(item.id.uuidString), .text(item.name), .text(item.category.rawValue),
                item.subtype.map { .text($0.rawValue) } ?? .null,
                .text(try jsonArray(item.scenarios.map(\.rawValue))), .text(item.status.rawValue),
                .integer(item.isWaterproof ? 1 : 0), date(item.laundryEntryDate),
                item.processedImage.map { .text($0.sha256) } ?? .null,
                item.originalImage.map { .text($0.sha256) } ?? .null,
                .real(item.dominantColor.red), .real(item.dominantColor.green),
                .real(item.dominantColor.blue), .real(item.dominantColor.alpha),
                item.secondaryColor.map { .real($0.red) } ?? .null, item.secondaryColor.map { .real($0.green) } ?? .null,
                item.secondaryColor.map { .real($0.blue) } ?? .null, item.secondaryColor.map { .real($0.alpha) } ?? .null,
                .text(item.dominantColorCategory.rawValue), .integer(Int64(item.warmthScore)),
                .text(try jsonArray(item.warmthLevels.map(\.rawValue))), .text(try jsonArray(item.seasons.map(\.rawValue))),
                item.brand.map { .text($0) } ?? .null, item.notes.map { .text($0) } ?? .null,
                .real(item.createdAt.timeIntervalSince1970), .real(item.updatedAt.timeIntervalSince1970),
            ])
    }

    /// 覆盖单品的全部可变字段（id 与录入时间不变）。
    /// - Returns: 是否找到该单品。
    @discardableResult
    public func updateItem(_ item: StoredItem) throws -> Bool {
        for ref in [item.processedImage, item.originalImage].compactMap({ $0 }) {
            try insertMedia(ref)
        }
        return try db.run("""
            UPDATE items SET
                name = ?, category = ?, subtype = ?, scenarios = ?, status = ?, is_waterproof = ?, laundry_entry_at = ?,
                processed_media = ?, original_media = ?,
                dominant_red = ?, dominant_green = ?, dominant_blue = ?, dominant_alpha = ?,
                secondary_red = ?, secondary_green = ?, secondary_blue = ?, secondary_alpha = ?,
                dominant_color_category = ?, warmth_score = ?, warmth_levels = ?, seasons = ?, brand = ?, notes = ?, updated_at = ?
            WHERE id = ?;
            """, [
                .text(item.name), .text(item.category.rawValue), item.subtype.map { .text($0.rawValue) } ?? .null,
                .text(try jsonArray(item.scenarios.map(\.rawValue))), .text(item.status.rawValue),
                .integer(item.isWaterproof ? 1 : 0), date(item.laundryEntryDate),
                item.processedImage.map { .text($0.sha256) } ?? .null, item.originalImage.map { .text($0.sha256) } ?? .null,
                .real(item.dominantColor.red), .real(item.dominantColor.green),
                .real(item.dominantColor.blue), .real(item.dominantColor.alpha),
                item.secondaryColor.map { .real($0.red) } ?? .null, item.secondaryColor.map { .real($0.green) } ?? .null,
                item.secondaryColor.map { .real($0.blue) } ?? .null, item.secondaryColor.map { .real($0.alpha) } ?? .null,
                .text(item.dominantColorCategory.rawValue), .integer(Int64(item.warmthScore)),
                .text(try jsonArray(item.warmthLevels.map(\.rawValue))), .text(try jsonArray(item.seasons.map(\.rawValue))),
                item.brand.map { .text($0) } ?? .null, item.notes.map { .text($0) } ?? .null,
                .real(item.updatedAt.timeIntervalSince1970), .text(item.id.uuidString),
            ]) > 0
    }

    /// 只更新流转相关字段与更新时间。
    public func updateItemState(id: UUID, state: ItemLifecycle.State, updatedAt: Date) throws {
        try db.run("UPDATE items SET status = ?, laundry_entry_at = ?, updated_at = ? WHERE id = ?;", [
            .text(state.status.rawValue), date(state.laundryEntryDate), .real(updatedAt.timeIntervalSince1970), .text(id.uuidString),
        ])
    }

    /// 删除单品。它在穿搭与穿着记录中的成员关系随之删除，穿搭与记录本身保留。
    @discardableResult
    public func deleteItem(id: UUID) throws -> Bool {
        try db.run("DELETE FROM items WHERE id = ?;", [.text(id.uuidString)]) > 0
    }

    /// 每件单品最近一次出现在穿着记录中的日期。
    public func lastWornDates() throws -> [UUID: Date] {
        var map: [UUID: Date] = [:]
        for row in try db.query("""
            SELECT wri.item_id AS item_id, MAX(wr.date) AS last_date
            FROM wear_record_items wri JOIN wear_records wr ON wr.id = wri.wear_record_id
            GROUP BY wri.item_id;
            """) {
            if let id = row.string("item_id").flatMap(UUID.init(uuidString:)), let date = row.double("last_date") {
                map[id] = Date(timeIntervalSince1970: date)
            }
        }
        return map
    }

    private func decodeItem(_ row: SQLiteRow) throws -> StoredItem {
        let id = row.string("id") ?? ""
        func fail(_ detail: String) -> StorageError { .corruptRow(table: "items", id: id, detail: detail) }
        guard let uuid = UUID(uuidString: id) else { throw fail("id") }
        func value<E: RawRepresentable>(_ column: String, _: E.Type) throws -> E where E.RawValue == String {
            guard let raw = row.string(column), let value = E(rawValue: raw) else { throw fail(column) }
            return value
        }
        func values<E: RawRepresentable>(_ column: String, _: E.Type) throws -> [E] where E.RawValue == String {
            guard let raw = row.string(column), let strings = try? decoder.decode([String].self, from: Data(raw.utf8)) else { throw fail(column) }
            return try strings.map { guard let value = E(rawValue: $0) else { throw fail(column) }; return value }
        }
        func media(_ prefix: String) throws -> MediaRef? {
            guard let sha = row.string("\(prefix)_sha") else { return nil }
            guard let format = row.string("\(prefix)_format").flatMap(ImageFormat.init(rawValue:)), let bytes = row.int("\(prefix)_bytes") else {
                throw fail("\(prefix) media")
            }
            return MediaRef(sha256: sha, format: format, byteCount: bytes)
        }
        guard let dr = row.double("dominant_red"), let dg = row.double("dominant_green"),
              let db = row.double("dominant_blue"), let da = row.double("dominant_alpha") else { throw fail("dominant color") }
        var secondary: StoredColor?
        if let sr = row.double("secondary_red"), let sg = row.double("secondary_green"),
           let sb = row.double("secondary_blue"), let sa = row.double("secondary_alpha") {
            secondary = StoredColor(red: sr, green: sg, blue: sb, alpha: sa)
        }
        return StoredItem(
            id: uuid,
            name: row.string("name") ?? "",
            category: try value("category", ClosetCore.Category.self),
            subtype: try row.string("subtype").map { raw in
                guard let subtype = Subtype(rawValue: raw) else { throw fail("subtype") }
                return subtype
            },
            scenarios: try values("scenarios", Scenario.self),
            status: try value("status", ItemStatus.self),
            isWaterproof: row.bool("is_waterproof") ?? false,
            laundryEntryDate: row.double("laundry_entry_at").map(Date.init(timeIntervalSince1970:)),
            dominantColor: StoredColor(red: dr, green: dg, blue: db, alpha: da),
            secondaryColor: secondary,
            dominantColorCategory: try value("dominant_color_category", ColorCategory.self),
            warmthScore: row.int("warmth_score") ?? 0,
            warmthLevels: try values("warmth_levels", WarmthLevel.self),
            seasons: try values("seasons", Season.self),
            brand: row.string("brand"),
            notes: row.string("notes"),
            createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? 0),
            processedImage: try media("pm"),
            originalImage: try media("om")
        )
    }

    // MARK: - 穿搭

    /// 按创建时间倒序返回穿搭，与 App 收藏夹的排序一致。
    public func outfits(favoritesOnly: Bool = false, ids: [UUID]? = nil) throws -> [StoredOutfit] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        if favoritesOnly { clauses.append("is_favorite = 1") }
        if let ids {
            if ids.isEmpty { return [] }
            clauses.append("id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")))")
            bindings.append(contentsOf: ids.map { .text($0.uuidString) })
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let rows = try db.query("SELECT * FROM outfits\(whereClause) ORDER BY created_at DESC, id;", bindings)
        let members = try memberMap(table: "outfit_items", ownerColumn: "outfit_id", owners: rows.compactMap { $0.string("id") })
        return try rows.map { row in
            let id = row.string("id") ?? ""
            func fail(_ detail: String) -> StorageError { .corruptRow(table: "outfits", id: id, detail: detail) }
            guard let uuid = UUID(uuidString: id) else { throw fail("id") }
            guard let source = row.string("source").flatMap(OutfitSource.init(rawValue:)) else { throw fail("source") }
            return StoredOutfit(
                id: uuid,
                name: row.string("name") ?? "",
                isFavorite: row.bool("is_favorite") ?? false,
                source: source,
                targetScenario: row.string("target_scenario").flatMap(Scenario.init(rawValue:)),
                targetWarmthLevel: row.string("target_warmth_level").flatMap(WarmthLevel.init(rawValue:)),
                members: members[id] ?? [],
                canvasLayout: row.data("canvas_layout"),
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0),
                updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? 0)
            )
        }
    }

    public func insertOutfit(_ outfit: StoredOutfit) throws {
        try db.run("""
            INSERT INTO outfits (id, name, is_favorite, source, target_scenario, target_warmth_level, canvas_layout, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(outfit.id.uuidString), .text(outfit.name), .integer(outfit.isFavorite ? 1 : 0),
                .text(outfit.source.rawValue), outfit.targetScenario.map { .text($0.rawValue) } ?? .null,
                outfit.targetWarmthLevel.map { .text($0.rawValue) } ?? .null, outfit.canvasLayout.map { .blob($0) } ?? .null,
                .real(outfit.createdAt.timeIntervalSince1970), .real(outfit.updatedAt.timeIntervalSince1970),
            ])
        try insertMembers(table: "outfit_items", ownerColumn: "outfit_id", owner: outfit.id, members: outfit.members)
    }

    // MARK: - 穿着记录

    /// 按日期倒序返回穿着记录，与 App 日历的排序一致。
    public func wearRecords(activeOnly: Bool = false, ids: [UUID]? = nil) throws -> [StoredWearRecord] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        if activeOnly { clauses.append("is_active = 1") }
        if let ids {
            if ids.isEmpty { return [] }
            clauses.append("id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")))")
            bindings.append(contentsOf: ids.map { .text($0.uuidString) })
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let rows = try db.query("SELECT * FROM wear_records\(whereClause) ORDER BY date DESC, id;", bindings)
        let members = try memberMap(table: "wear_record_items", ownerColumn: "wear_record_id", owners: rows.compactMap { $0.string("id") })
        return try rows.map { row in
            let id = row.string("id") ?? ""
            guard let uuid = UUID(uuidString: id) else { throw StorageError.corruptRow(table: "wear_records", id: id, detail: "id") }
            return StoredWearRecord(
                id: uuid,
                date: Date(timeIntervalSince1970: row.double("date") ?? 0),
                isActive: row.bool("is_active") ?? false,
                outfitID: row.string("outfit_id").flatMap(UUID.init(uuidString:)),
                members: members[id] ?? [],
                notes: row.string("notes"),
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0)
            )
        }
    }

    public func activeWearRecord() throws -> StoredWearRecord? {
        try wearRecords(activeOnly: true).first
    }

    public func insertWearRecord(_ record: StoredWearRecord) throws {
        try db.run("""
            INSERT INTO wear_records (id, date, is_active, outfit_id, notes, created_at) VALUES (?, ?, ?, ?, ?, ?);
            """, [
                .text(record.id.uuidString), .real(record.date.timeIntervalSince1970), .integer(record.isActive ? 1 : 0),
                record.outfitID.map { .text($0.uuidString) } ?? .null, record.notes.map { .text($0) } ?? .null,
                .real(record.createdAt.timeIntervalSince1970),
            ])
        try insertMembers(table: "wear_record_items", ownerColumn: "wear_record_id", owner: record.id, members: record.members)
    }

    /// 把所有「正在穿」记录转为历史（`WearService.deactivateActiveRecords`）。
    public func deactivateWearRecords() throws {
        try db.run("UPDATE wear_records SET is_active = 0 WHERE is_active = 1;")
    }

    public func setWearRecordActive(id: UUID, _ active: Bool) throws {
        try db.run("UPDATE wear_records SET is_active = ? WHERE id = ?;", [.integer(active ? 1 : 0), .text(id.uuidString)])
    }

    @discardableResult
    public func deleteWearRecord(id: UUID) throws -> Bool {
        try db.run("DELETE FROM wear_records WHERE id = ?;", [.text(id.uuidString)]) > 0
    }

    @discardableResult
    public func deleteOutfit(id: UUID) throws -> Bool {
        try db.run("DELETE FROM outfits WHERE id = ?;", [.text(id.uuidString)]) > 0
    }

    // MARK: - 设置

    /// 读取一项设置（JSON 文本）。
    public func setting(_ key: String) throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = ?;", [.text(key)]).first?.string("value")
    }

    public func putSetting(_ key: String, json: String, updatedAt: Date) throws {
        try db.run("""
            INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
            """, [.text(key), .text(json), .real(updatedAt.timeIntervalSince1970)])
    }

    // MARK: - 成员关系

    private func memberMap(table: String, ownerColumn: String, owners: [String]) throws -> [String: [SlottedItemID]] {
        guard !owners.isEmpty else { return [:] }
        var map: [String: [SlottedItemID]] = [:]
        // 分批查询，避免超过 SQLite 的参数个数上限。
        for batch in stride(from: 0, to: owners.count, by: 500).map({ Array(owners[$0..<min($0 + 500, owners.count)]) }) {
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ", ")
            let rows = try db.query(
                "SELECT \(ownerColumn) AS owner, item_id, slot FROM \(table) WHERE \(ownerColumn) IN (\(placeholders)) ORDER BY \(ownerColumn), position;",
                batch.map { .text($0) })
            for row in rows {
                guard let owner = row.string("owner"), let itemID = row.string("item_id").flatMap(UUID.init(uuidString:)) else { continue }
                map[owner, default: []].append(SlottedItemID(itemID: itemID, slot: row.string("slot").flatMap(OutfitSlot.init(rawValue:))))
            }
        }
        return map
    }

    private func insertMembers(table: String, ownerColumn: String, owner: UUID, members: [SlottedItemID]) throws {
        for (position, member) in members.enumerated() {
            try db.run("INSERT INTO \(table) (\(ownerColumn), item_id, position, slot) VALUES (?, ?, ?, ?);", [
                .text(owner.uuidString), .text(member.itemID.uuidString), .integer(Int64(position)),
                member.slot.map { .text($0.rawValue) } ?? .null,
            ])
        }
    }

    // MARK: - 媒体

    public func insertMedia(_ ref: MediaRef) throws {
        try db.run("INSERT OR IGNORE INTO media (sha256, format, byte_count, created_at) VALUES (?, ?, ?, ?);", [
            .text(ref.sha256), .text(ref.format.rawValue), .integer(Int64(ref.byteCount)), .real(Date().timeIntervalSince1970),
        ])
    }

    /// 不再被任何单品引用的媒体哈希。
    public func unreferencedMediaHashes() throws -> [String] {
        try db.query("""
            SELECT sha256 FROM media
            WHERE sha256 NOT IN (SELECT processed_media FROM items WHERE processed_media IS NOT NULL)
              AND sha256 NOT IN (SELECT original_media FROM items WHERE original_media IS NOT NULL);
            """).compactMap { $0.string("sha256") }
    }

    public func referencedMediaHashes() throws -> Set<String> {
        Set(try db.query("SELECT sha256 FROM media;").compactMap { $0.string("sha256") })
    }

    public func deleteMediaRows(_ hashes: [String]) throws {
        for hash in hashes {
            try db.run("DELETE FROM media WHERE sha256 = ?;", [.text(hash)])
        }
    }

    // MARK: - 整体

    public func existingIDs() throws -> ExistingIDs {
        func ids(_ table: String) throws -> Set<UUID> {
            Set(try db.query("SELECT id FROM \(table);").compactMap { $0.string("id").flatMap(UUID.init(uuidString:)) })
        }
        return ExistingIDs(items: try ids("items"), outfits: try ids("outfits"), wearRecords: try ids("wear_records"))
    }

    public func counts() throws -> StoreCounts {
        func count(_ table: String) throws -> Int {
            try db.query("SELECT COUNT(*) AS n FROM \(table);").first?.int("n") ?? 0
        }
        return StoreCounts(items: try count("items"), outfits: try count("outfits"),
                           wearRecords: try count("wear_records"), media: try count("media"))
    }

    /// 清空衣橱数据（单品、穿搭、穿着记录）。媒体行由垃圾回收清理。
    public func deleteAllWardrobeData() throws {
        try db.run("DELETE FROM wear_records;")
        try db.run("DELETE FROM outfits;")
        try db.run("DELETE FROM items;")
    }

    // MARK: - 编码工具

    private func jsonArray(_ values: [String]) throws -> String {
        String(decoding: try encoder.encode(values), as: UTF8.self)
    }

    private func date(_ value: Date?) -> SQLiteValue {
        value.map { .real($0.timeIntervalSince1970) } ?? .null
    }
}
