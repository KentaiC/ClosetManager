import Foundation

/// 差旅打包计算（纯逻辑，与 UI 解耦）。
public enum TravelService {
    /// 内裤/打底携带数量的硬编码规则。
    /// 默认：每天 1 条 + 1 条备用；上限封顶 5（长途差旅必然有洗衣条件）。
    public static func underwearCount(days: Int) -> Int {
        let base = max(days, 1) + 1
        return min(base, packingCap)
    }

    /// 袜子携带数量，同内裤规则。
    public static func socksCount(days: Int) -> Int {
        underwearCount(days: days)
    }

    /// 携带上限。
    public static let packingCap = 5

    /// 是否显示「已封顶」贴心提示（天数 > 4 时）。
    public static func showsCapHint(days: Int) -> Bool {
        days > 4
    }
}

extension TravelService {
    /// 打包建议：按行程跑若干套穿搭，取去重后的单品集合，保持首次出现的顺序（与 App 的差旅页面相同）。
    public static func packingSuggestion<Item: WardrobeItemRepresentable>(from result: OutfitGenerationResult<Item>) -> [Item] {
        var seen = Set<UUID>()
        var unique: [Item] = []
        for draft in result.drafts {
            for item in draft.allItems where !seen.contains(item.id) {
                seen.insert(item.id)
                unique.append(item)
            }
        }
        return unique
    }
}
