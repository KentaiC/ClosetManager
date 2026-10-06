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
