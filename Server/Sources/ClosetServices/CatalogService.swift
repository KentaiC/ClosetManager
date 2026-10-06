import Foundation
import ClosetCore
import ClosetStorage

/// 穿搭及其成员单品。
public struct ResolvedOutfit: Sendable {
    public var outfit: StoredOutfit
    /// 按保存顺序排列，已删除的单品不在其中。
    public var items: [StoredItem]
}

/// 穿着记录及其成员单品。
public struct ResolvedWearRecord: Sendable {
    public var record: StoredWearRecord
    public var items: [StoredItem]
}

/// 只读查询服务：把存储记录组装成界面需要的结构。
public struct CatalogService: Sendable {
    let store: ClosetStore

    public init(store: ClosetStore) {
        self.store = store
    }

    public func items(_ filter: ItemFilter = ItemFilter()) async throws -> [StoredItem] {
        try await store.read { try $0.items(filter) }
    }

    public func item(id: UUID) async throws -> StoredItem? {
        try await store.read { try $0.item(id: id) }
    }

    public func outfits(favoritesOnly: Bool) async throws -> [ResolvedOutfit] {
        try await store.read { session in
            let outfits = try session.outfits(favoritesOnly: favoritesOnly)
            let items = try Self.itemMap(session, ids: outfits.flatMap(\.itemIDs))
            return outfits.map { ResolvedOutfit(outfit: $0, items: $0.itemIDs.compactMap { items[$0] }) }
        }
    }

    public func wearRecords(activeOnly: Bool = false) async throws -> [ResolvedWearRecord] {
        try await store.read { session in
            let records = try session.wearRecords(activeOnly: activeOnly)
            let items = try Self.itemMap(session, ids: records.flatMap(\.itemIDs))
            return records.map { ResolvedWearRecord(record: $0, items: $0.itemIDs.compactMap { items[$0] }) }
        }
    }

    public func resolve(_ record: StoredWearRecord) async throws -> ResolvedWearRecord {
        try await store.read { session in
            let items = try Self.itemMap(session, ids: record.itemIDs)
            return ResolvedWearRecord(record: record, items: record.itemIDs.compactMap { items[$0] })
        }
    }

    public func resolve(_ outfit: StoredOutfit) async throws -> ResolvedOutfit {
        try await store.read { session in
            let items = try Self.itemMap(session, ids: outfit.itemIDs)
            return ResolvedOutfit(outfit: outfit, items: outfit.itemIDs.compactMap { items[$0] })
        }
    }

    public func counts() async throws -> StoreCounts {
        try await store.read { try $0.counts() }
    }

    static func itemMap(_ session: StoreSession, ids: [UUID]) throws -> [UUID: StoredItem] {
        let unique = Array(Set(ids))
        var map: [UUID: StoredItem] = [:]
        for start in stride(from: 0, to: unique.count, by: 500) {
            let batch = Array(unique[start..<min(start + 500, unique.count)])
            for item in try session.items(ItemFilter(ids: batch)) { map[item.id] = item }
        }
        return map
    }
}
