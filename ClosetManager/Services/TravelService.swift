import Foundation

/// 差旅打包计算（纯逻辑，与 UI 解耦）。
enum TravelService {
    /// 内裤/打底携带数量的硬编码规则。
    /// 默认：每天 1 条 + 1 条备用；上限封顶 5（长途差旅必然有洗衣条件）。
    static func underwearCount(days: Int) -> Int {
        let base = max(days, 1) + 1
        return min(base, packingCap)
    }

    /// 袜子携带数量，同内裤规则。
    static func socksCount(days: Int) -> Int {
        underwearCount(days: days)
    }

    /// 携带上限。
    static let packingCap = 5

    /// 是否显示「已封顶」贴心提示（天数 > 4 时）。
    static func showsCapHint(days: Int) -> Bool {
        days > 4
    }
}
