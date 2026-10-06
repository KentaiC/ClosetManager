import Foundation

/// 单品字段的默认值规则，App 的 `ClothingItem` 与服务端导入共用。
public enum ItemDefaults {
    /// 保暖标签：调用方未显式给出时，由保暖度派生为单一档位。
    public static func resolvedWarmthLevels(_ explicit: [WarmthLevel], warmthScore: Int) -> [WarmthLevel] {
        explicit.isEmpty ? [WarmthLevel.from(score: warmthScore)] : explicit
    }

    /// 由颜色与种类组合默认名称，如「绿色短裤」「黑色卫衣」。
    /// 无子类时退回顶层分类名（如「绿色下装」）。
    public static func defaultName(color: StoredColor, subtype: Subtype?, category: Category) -> String {
        let colorName = ColorCategory.classify(color).displayName
        let typeName = subtype?.displayName ?? category.displayName
        return colorName + typeName
    }
}

extension ItemDefaults {
    /// 列表与卡片上显示的标题：名称为空时显示分类名（与 App 的 ItemCard、TakeOffSheet 相同）。
    public static func displayTitle(name: String, category: Category) -> String {
        name.isEmpty ? category.displayName : name
    }
}
