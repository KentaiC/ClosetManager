import Foundation

/// 衣橱数据分析（纯函数，与 UI 和持久化解耦）。
///
/// 注意：本应用刻意**不包含任何价格 / 成本 / 单次穿着成本(CPW)** 的统计字段或逻辑。
public enum AnalyticsService {

    /// 库存透视：各分类的件数（仅返回非空分类）。
    public static func inventoryByCategory<Item: WardrobeItemRepresentable>(
        _ items: [Item]
    ) -> [(category: Category, count: Int)] {
        Category.allCases
            .map { category in (category, items.filter { $0.category == category }.count) }
            .filter { $0.1 > 0 }
    }

    /// 衣橱颜色库存：各颜色桶在衣橱里的件数（按件数降序，供树形图用）。
    public static func colorInventory<Item: WardrobeItemRepresentable>(
        _ items: [Item]
    ) -> [(color: ColorCategory, count: Int)] {
        var counts: [ColorCategory: Int] = [:]
        for item in items {
            counts[item.dominantColorCategory, default: 0] += 1
        }
        return counts
            .map { (color: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// 色彩偏好：历史穿搭记录中，各颜色桶被穿着的次数（按次数降序）。
    public static func colorFrequency<Record: WearRecordRepresentable>(
        _ records: [Record]
    ) -> [(color: ColorCategory, count: Int)] {
        var counts: [ColorCategory: Int] = [:]
        for record in records {
            for item in record.items {
                counts[item.dominantColorCategory, default: 0] += 1
            }
        }
        return counts
            .map { (color: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// 穿着活跃度：每天（startOfDay）的穿搭打卡次数。
    /// - Parameter calendar: 按哪个日历切分日期；App 使用默认的 `Calendar.current`。
    public static func dailyActivity<Record: WearRecordRepresentable>(
        _ records: [Record],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            counts[day, default: 0] += 1
        }
        return counts
    }
}
