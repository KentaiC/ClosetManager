import Foundation
import SwiftData

/// 衣橱单品：录入并经过智能处理（Vision 抠图 + CoreImage 取色）后的核心数据实体。
@Model
final class ClothingItem {
    /// 唯一标识。
    @Attribute(.unique) var id: UUID

    /// 名称 / 标题（如「白色基础款 T 恤」）。
    var name: String

    /// 分类（互斥单选）。
    var category: Category

    /// 适用场景（可多选）。SwiftData 以 JSON 形式持久化该枚举数组。
    var scenarios: [Scenario]

    /// 状态机：在衣橱 / 在洗衣袋。
    var status: ItemStatus

    // MARK: - 图像（Vision 抠图）

    /// 抠图后（去背景）的主体图像数据。大对象，使用外部存储。
    @Attribute(.externalStorage) var processedImageData: Data?

    /// 原始导入图像数据（保留以便后续重新抠图 / 编辑）。
    @Attribute(.externalStorage) var originalImageData: Data?

    // MARK: - 颜色（CoreImage 取色，阶段三接入）

    /// 主色（占比最高）。阶段二录入时先用中性占位色，阶段三由 CoreImage 覆盖。
    var dominantColor: StoredColor

    /// 辅色（占比次高，可能为空）。
    var secondaryColor: StoredColor?

    /// 主色归类（落库以便看板快速做颜色占比聚合）。
    /// 由 `init` / `refreshColorCategory()` 依据 `dominantColor` 自动派生，不需手动维护。
    var dominantColorCategory: ColorCategory

    // MARK: - 保暖程度与季节

    /// 保暖标签（可多选，如一件薄外套适配「凉爽 + 温和」）。穿搭引擎据此匹配当前天气。
    var warmthLevels: [WarmthLevel]

    /// 适用季节（默认由 `warmthLevels` 自动推导，允许用户手动覆盖）。
    var seasons: [Season]

    // MARK: - 其它元数据

    var brand: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - 关系

    /// 该单品参与的穿搭（多对多）。反向关系声明在 `Outfit.items`。
    var outfits: [Outfit]

    /// 该单品出现过的穿搭日历记录（多对多）。反向关系声明在 `WearRecord.items`。
    var wearRecords: [WearRecord]

    init(
        id: UUID = UUID(),
        name: String = "",
        category: Category,
        scenarios: [Scenario] = [],
        status: ItemStatus = .inWardrobe,
        processedImageData: Data? = nil,
        originalImageData: Data? = nil,
        dominantColor: StoredColor = StoredColor(red: 0.5, green: 0.5, blue: 0.5),
        secondaryColor: StoredColor? = nil,
        warmthLevels: [WarmthLevel] = [],
        seasons: [Season]? = nil,
        brand: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.scenarios = scenarios
        self.status = status
        self.processedImageData = processedImageData
        self.originalImageData = originalImageData
        self.dominantColor = dominantColor
        self.secondaryColor = secondaryColor
        self.dominantColorCategory = ColorCategory.classify(dominantColor)
        self.warmthLevels = warmthLevels
        // 季节未显式指定时，由保暖标签自动推导。
        self.seasons = seasons ?? Season.derive(from: warmthLevels)
        self.brand = brand
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.outfits = []
        self.wearRecords = []
    }
}

// MARK: - 业务便捷方法（穿搭引擎 / 录入校验使用）

extension ClothingItem {
    /// 是否可用于穿搭（在衣橱中）。
    var isAvailable: Bool { status == .inWardrobe }

    /// 重新依据当前主色刷新颜色归类（编辑主色后调用）。
    func refreshColorCategory() {
        dominantColorCategory = ColorCategory.classify(dominantColor)
    }

    /// 是否适配指定的当前天气保暖标签。
    func isSuitable(forWarmth warmth: WarmthLevel) -> Bool {
        warmthLevels.contains(warmth)
    }

    /// 是否适配指定场景。
    func isSuitable(forScenario scenario: Scenario) -> Bool {
        scenarios.contains(scenario)
    }

    /// 场景组合是否存在冲突（如同时勾选「正式」与「运动」）。
    /// 供录入 / 编辑层做即时校验提示。
    var hasScenarioConflict: Bool {
        let current = Set(scenarios)
        return scenarios.contains { !$0.conflictingScenarios.isDisjoint(with: current) }
    }
}
