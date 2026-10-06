import Foundation
import ClosetCore
import ClosetStorage

/// 穿着与洗衣流转，对应 App 的 `WearService`。状态变化规则来自共享核心 `ItemLifecycle`。
public struct LifecycleService: Sendable {
    let store: ClosetStore
    let now: @Sendable () -> Date

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// 今天穿这套：先把其它正在穿的记录转为历史，再新建一条正在穿的记录（`wearToday` / `wearOutfit`）。
    /// 与 App 相同，穿着不改变单品状态。
    public func wear(members: [SlottedItemID], outfitID: UUID? = nil) async throws -> StoredWearRecord {
        guard !members.isEmpty else { throw ServiceError.invalid("穿搭中没有单品。") }
        let timestamp = now()
        return try await store.transaction { session in
            try Self.requireItems(session, members.map(\.itemID))
            if let outfitID, try session.outfits(ids: [outfitID]).isEmpty { throw ServiceError.notFound("未找到该穿搭。") }
            try session.deactivateWearRecords()
            let record = StoredWearRecord(id: UUID(), date: timestamp, isActive: true, outfitID: outfitID,
                                          members: members, notes: nil, createdAt: timestamp)
            try session.insertWearRecord(record)
            return record
        }
    }

    /// 穿一套已保存的穿搭：成员取自穿搭当前的单品。
    public func wearOutfit(id: UUID) async throws -> StoredWearRecord {
        guard let outfit = try await store.read({ try $0.outfits(ids: [id]).first }) else {
            throw ServiceError.notFound("未找到该穿搭。")
        }
        return try await wear(members: outfit.members, outfitID: id)
    }

    /// 脱下：勾选的单品进洗衣袋，其余回衣橱，记录转为历史（`WearService.takeOff`）。
    public func takeOff(recordID: UUID, laundryItemIDs: Set<UUID>) async throws -> StoredWearRecord {
        let timestamp = now()
        return try await store.transaction { session in
            guard var record = try session.wearRecords(ids: [recordID]).first else {
                throw ServiceError.notFound("未找到该穿着记录。")
            }
            guard record.isActive else { throw ServiceError.conflict("这条记录已经不是正在穿的穿搭。") }
            let memberIDs = Set(record.itemIDs)
            guard laundryItemIDs.isSubset(of: memberIDs) else { throw ServiceError.invalid("要放进洗衣袋的单品不在这套穿搭中。") }
            for item in try session.items(ItemFilter(ids: record.itemIDs)) {
                let state = ItemLifecycle.takeOff(sentToLaundry: laundryItemIDs.contains(item.id), now: timestamp)
                try session.updateItemState(id: item.id, state: state, updatedAt: timestamp)
            }
            try session.setWearRecordActive(id: recordID, false)
            record.isActive = false
            return record
        }
    }

    /// 洗净放回（`WearService.returnToWardrobe`）。只接受当前在洗衣袋中的单品。
    public func returnFromLaundry(itemIDs: [UUID]) async throws -> [StoredItem] {
        guard !itemIDs.isEmpty else { throw ServiceError.invalid("没有选择单品。") }
        let timestamp = now()
        return try await store.transaction { session in
            let items = try Self.requireItems(session, itemIDs)
            if let item = items.first(where: { $0.status != .inLaundry }) {
                throw ServiceError.conflict("「\(ItemDefaults.displayTitle(name: item.name, category: item.category))」不在洗衣袋中。")
            }
            for item in items {
                try session.updateItemState(id: item.id, state: ItemLifecycle.returnFromLaundry(), updatedAt: timestamp)
            }
            return try session.items(ItemFilter(ids: itemIDs))
        }
    }

    /// 装入行李箱（`WearService.packIntoLuggage`）。
    public func pack(itemIDs: [UUID]) async throws -> [StoredItem] {
        guard !itemIDs.isEmpty else { throw ServiceError.invalid("没有选择单品。") }
        let timestamp = now()
        return try await store.transaction { session in
            for item in try Self.requireItems(session, itemIDs) {
                let state = ItemLifecycle.pack(.init(status: item.status, laundryEntryDate: item.laundryEntryDate))
                try session.updateItemState(id: item.id, state: state, updatedAt: timestamp)
            }
            return try session.items(ItemFilter(ids: itemIDs))
        }
    }

    /// 结束差旅：行李箱中的单品全部取出回到衣橱（`WearService.unpackAllLuggage`）。
    /// - Returns: 取出的件数。
    @discardableResult
    public func unpackAll() async throws -> Int {
        let timestamp = now()
        return try await store.transaction { session in
            let packed = try session.items(ItemFilter(status: .inLuggage))
            for item in packed {
                let state = ItemLifecycle.unpack(.init(status: item.status, laundryEntryDate: item.laundryEntryDate))
                try session.updateItemState(id: item.id, state: state, updatedAt: timestamp)
            }
            return packed.count
        }
    }

    public func deleteWearRecord(id: UUID) async throws {
        let deleted = try await store.transaction { try $0.deleteWearRecord(id: id) }
        guard deleted else { throw ServiceError.notFound("未找到该穿着记录。") }
    }

    @discardableResult
    static func requireItems(_ session: StoreSession, _ ids: [UUID]) throws -> [StoredItem] {
        guard Set(ids).count == ids.count else { throw ServiceError.invalid("同一件单品出现了多次。") }
        let items = try session.items(ItemFilter(ids: ids))
        guard items.count == ids.count else { throw ServiceError.notFound("部分单品不存在，可能已被删除。") }
        return items
    }
}
