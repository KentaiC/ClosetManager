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
    /// 更换图片。为 nil 时图片与辅色保持不变。
    public var images: ImageChange?

    public init(
        name: String, category: ClosetCore.Category, subtype: Subtype?, scenarios: [Scenario], warmthScore: Int,
        seasons: [Season], status: ItemStatus, isWaterproof: Bool, brand: String?, notes: String?, dominantColor: StoredColor,
        images: ImageChange? = nil
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
        self.images = images
    }
}

/// 新的图片与辅色，对应 App 中重新选图后 `ItemDraftModel` 的图像字段。
/// 图片必须已经通过 `ImageService.upload` 上传。
public struct ImageChange: Sendable, Equatable {
    public var originalSHA256: String
    public var processedSHA256: String?
    public var secondaryColor: StoredColor?

    public init(originalSHA256: String, processedSHA256: String?, secondaryColor: StoredColor?) {
        self.originalSHA256 = originalSHA256
        self.processedSHA256 = processedSHA256
        self.secondaryColor = secondaryColor
    }
}

/// 单品的新增、编辑与删除。
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

    /// 新增单品，规则与 App 的 `ItemDraftModel.makeNewItem` 相同：至少要有一张图片；
    /// 名称为空时自动命名；保暖标签由保暖度派生；季节按提交的内容保存（未调整时为空，审计 M-04，保持现状）；
    /// 即使状态为「在洗衣袋」也不设入袋时间，与 App 新建单品时相同。
    public func create(_ edit: ItemEdit) async throws -> StoredItem {
        try Self.validate(edit)
        guard let images = edit.images else { throw ServiceError.invalid("新增单品需要一张图片。") }
        let timestamp = now()
        return try await store.transaction { session in
            let (original, processed) = try Self.resolve(images, in: session)
            let item = StoredItem(
                id: UUID(), name: Self.resolvedName(edit), category: edit.category, subtype: edit.subtype,
                scenarios: Scenario.allCases.filter(edit.scenarios.contains), status: edit.status, isWaterproof: edit.isWaterproof,
                laundryEntryDate: nil, dominantColor: edit.dominantColor, secondaryColor: images.secondaryColor,
                dominantColorCategory: ColorCategory.classify(edit.dominantColor), warmthScore: edit.warmthScore,
                warmthLevels: [WarmthLevel.from(score: edit.warmthScore)], seasons: Season.allCases.filter(edit.seasons.contains),
                brand: edit.brand?.isEmpty == true ? nil : edit.brand, notes: edit.notes?.isEmpty == true ? nil : edit.notes,
                createdAt: timestamp, updatedAt: timestamp, processedImage: processed, originalImage: original)
            try session.insertItem(item)
            return item
        }
    }

    /// 按 App 编辑页保存时的规则更新单品（`ItemDraftModel.apply(to:)`）：
    /// 保暖标签由保暖度派生，颜色归类随主色刷新，更新时间设为当前时间。
    /// 没有更换图片时图片与辅色不变；更换图片时一并替换原图、抠图结果与辅色，旧图片在没有其它引用时清理。
    /// 与 App 相同，修改状态不会改动入袋时间（审计 M-01，保持现状）。
    public func update(id: UUID, with edit: ItemEdit) async throws -> StoredItem {
        try Self.validate(edit)
        let timestamp = now()
        let updated = try await store.transaction { session in
            guard var item = try session.item(id: id) else { throw ServiceError.notFound("未找到该单品。") }
            item.name = Self.resolvedName(edit)
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
            if let images = edit.images {
                (item.originalImage, item.processedImage) = try Self.resolve(images, in: session)
                item.secondaryColor = images.secondaryColor
            }
            item.updatedAt = timestamp
            try session.updateItem(item)
            return item
        }
        if edit.images != nil { try await store.collectUnreferencedMedia(now: timestamp) }
        return updated
    }

    static func resolvedName(_ edit: ItemEdit) -> String {
        edit.name.isEmpty ? ItemDefaults.defaultName(color: edit.dominantColor, subtype: edit.subtype, category: edit.category) : edit.name
    }

    /// 把图片哈希解析为已登记的媒体引用。
    static func resolve(_ images: ImageChange, in session: StoreSession) throws -> (original: MediaRef, processed: MediaRef?) {
        guard let original = try session.media(sha256: images.originalSHA256) else {
            throw ServiceError.invalid("原图不存在或已过期，请重新上传。")
        }
        var processed: MediaRef?
        if let sha = images.processedSHA256 {
            guard let ref = try session.media(sha256: sha) else { throw ServiceError.invalid("抠图结果不存在或已过期，请重新上传。") }
            processed = ref
        }
        if let color = images.secondaryColor {
            for component in [color.red, color.green, color.blue, color.alpha] {
                guard component.isFinite, (0...1).contains(component) else { throw ServiceError.invalid("颜色分量必须在 0 到 1 之间。") }
            }
        }
        return (original, processed)
    }

    /// 删除单品；它在穿搭与记录中的成员关系一并删除，图片在没有其它引用时清理。
    public func delete(id: UUID) async throws {
        let deleted = try await store.transaction { try $0.deleteItem(id: id) }
        guard deleted else { throw ServiceError.notFound("未找到该单品。") }
        try await store.collectUnreferencedMedia()
    }
}
