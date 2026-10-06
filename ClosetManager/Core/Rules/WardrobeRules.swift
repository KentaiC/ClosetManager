import Foundation

/// 衣橱日常规则中的固定参数。
public enum WardrobeRules {
    /// 洗衣袋滞留预警阈值：入袋超过 4 天（与 App 的洗衣房页面一致）。
    public static let laundryRetentionWarningInterval: TimeInterval = 4 * 24 * 3600

    /// 是否应显示滞留预警。没有入袋时间时不预警。
    public static func isLaundryRetentionWarning(entryDate: Date?, now: Date) -> Bool {
        guard let entryDate else { return false }
        return now.timeIntervalSince(entryDate) > laundryRetentionWarningInterval
    }

    /// 「吃灰」判定的天数：过去 90 天未穿（与 App 的高级筛选页面一致）。
    public static let unwornDays = 90
}
