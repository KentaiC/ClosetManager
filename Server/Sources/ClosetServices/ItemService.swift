import Foundation
import ClosetCore
import ClosetStorage

/// 编辑单品时提交的全部可编辑字段，对应 App 编辑页的表单。
public struct ItemEdit: Sendable, Equatable {
    /// 为空时使用「颜色 + 子类」自动命名，与 App 相同。
    public var name: String
    public var category: ClosetCore.Category
    public var subtype: Subtype?
    public var scenarios: [Scenario]
    public var warmthScore: Int
    public var seasons: [Season]
    public var status: ItemStatus
    public var isWaterproof: Bool
    public var brand: String?
    public var notes: String?
    public var dominantColor: StoredColor

    public init(
        name: String, category: ClosetCore.Category, subtype: Subtype?, scenarios: [Scenario], warmthScore: Int,
        seasons: [Season], status: ItemStatus, isWaterproof: Bool, brand: String?, notes: String?, dominantColor: StoredColor
    ) {
        self.name = name
        self.category = category
        self.subtype = subtype
        self.scenarios = scenarios
        self.warmthScore = warmthScore
        self.seasons = seasons
        self.status = status
        self.isWaterproof = isWaterproof
        self.brand = brand
        self.notes = notes
        self.dominantColor = dominantColor
    }
}

/// 单品的编辑与删除。
public struct ItemService: Sendable {
    let store: ClosetStore
    let now: @Sendable () -> Date

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// 校验编辑内容。
    public static func validate(_ edit: ItemEdit) throws {
        if let subtype = edit.subtype, subtype.category != edit.category {
            throw ServiceError.invalid("子类「\(subtype.displayName)」不属于分类「\(edit.category.displayName)」。")
        }
        guard (1...100).contains(edit.warmthScore) else { throw ServiceError.invalid("保暖度必须在 1 到 100 之间。") }
        let color = edit.dominantColor
        for component in [color.red, color.green, color.blue, color.alpha] {
            guard component.isFinite, (0...1).contains(component) else { throw ServiceError.invalid("颜色分量必须在 0 到 1 之间。") }
        }
    }

    /// 按 App 编辑页保存时的规则更新单品（`ItemDraftModel.apply(to:)`）：
    /// 保暖标签由保暖度派生，颜色归类随主色刷新，更新时间设为当前时间；图片与辅色不变。
    /// 与 App 相同，修改状态不会改动入袋时间（审计 M-01，保持现状）。
    public func update(id: UUID, with edit: ItemEdit) async throws -> StoredItem {
        try Self.validate(edit)
        let timestamp = now()
        return try await store.transaction { session in
            guard var item = try session.item(id: id) else { throw ServiceError.notFound("未找到该单品。") }
            item.name = edit.name.isEmpty
                ? ItemDefaults.defaultName(color: edit.dominantColor, subtype: edit.subtype, category: edit.category)
                : edit.name
            item.category = edit.category
            item.subtype = edit.subtype
            item.scenarios = Scenario.allCases.filter(edit.scenarios.contains)
            item.warmthScore = edit.warmthScore
            item.warmthLevels = [WarmthLevel.from(score: edit.warmthScore)]
            item.seasons = Season.allCases.filter(edit.seasons.contains)
            item.status = edit.status
            item.isWaterproof = edit.isWaterproof
            item.brand = edit.brand?.isEmpty == true ? nil : edit.brand
            item.notes = edit.notes?.isEmpty == true ? nil : edit.notes
            item.dominantColor = edit.dominantColor
            item.dominantColorCategory = ColorCategory.classify(edit.dominantColor)
            item.updatedAt = timestamp
            try session.updateItem(item)
            return item
        }
    }

    /// 删除单品；它在穿搭与记录中的成员关系一并删除，图片在没有其它引用时清理。
    public func delete(id: UUID) async throws {
        let deleted = try await store.transaction { try $0.deleteItem(id: id) }
        guard deleted else { throw ServiceError.notFound("未找到该单品。") }
        try await store.collectUnreferencedMedia()
    }
}
