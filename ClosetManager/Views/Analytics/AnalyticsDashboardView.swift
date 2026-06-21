import SwiftUI
import SwiftData
import Charts

/// 衣橱数据分析看板（Swift Charts）。
///
/// 三大模块：库存透视（各分类件数）、色彩偏好（历史穿着颜色排名）、活跃度热力图。
/// 明确不含任何价格 / 成本 / CPW 字段或统计。
struct AnalyticsDashboardView: View {
    @Query private var items: [ClothingItem]
    @Query(sort: \WearRecord.date, order: .reverse) private var records: [WearRecord]

    private var inventory: [(category: Category, count: Int)] {
        AnalyticsService.inventoryByCategory(items)
    }
    private var colorFreq: [(color: ColorCategory, count: Int)] {
        AnalyticsService.colorFrequency(records)
    }
    private var colorInventory: [(color: ColorCategory, count: Int)] {
        AnalyticsService.colorInventory(items)
    }
    private var activity: [Date: Int] {
        AnalyticsService.dailyActivity(records)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    inventoryCard
                    treemapCard
                    colorCard
                    activityCard
                }
                .padding()
            }
            .navigationTitle("看板")
        }
    }

    // MARK: - 库存透视

    private var inventoryCard: some View {
        card(title: "衣橱库存透视", subtitle: "各分类件数") {
            if inventory.isEmpty {
                placeholder("衣橱还没有单品")
            } else {
                Chart(inventory, id: \.category) { row in
                    BarMark(
                        x: .value("件数", row.count),
                        y: .value("分类", row.category.displayName)
                    )
                    .foregroundStyle(.tint)
                    .annotation(position: .trailing) {
                        Text("\(row.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(inventory.count) * 38 + 10)
            }
        }
    }

    // MARK: - 色彩偏好

    private var colorCard: some View {
        card(title: "色彩偏好分析", subtitle: "历史穿搭中最常穿的颜色") {
            if colorFreq.isEmpty {
                placeholder("还没有穿搭记录")
            } else {
                Chart(colorFreq, id: \.color) { row in
                    BarMark(
                        x: .value("次数", row.count),
                        y: .value("颜色", row.color.displayName)
                    )
                    .foregroundStyle(swatchColor(for: row.color))
                    .annotation(position: .trailing) {
                        Text("\(row.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(colorFreq.count) * 34 + 10)
            }
        }
    }

    // MARK: - 颜色树形图

    private var treemapCard: some View {
        card(title: "衣橱颜色占比", subtitle: "色块面积代表该颜色的件数") {
            if colorInventory.isEmpty {
                placeholder("衣橱还没有单品")
            } else {
                ColorTreemapView(
                    tiles: colorInventory.map { row in
                        ColorTreemapView.Tile(
                            label: row.color.displayName,
                            count: row.count,
                            fill: swatchColor(for: row.color),
                            text: textColor(for: row.color)
                        )
                    }
                )
            }
        }
    }

    /// 树形图块上的对比文字色：浅底用黑字，深底用白字。
    private func textColor(for category: ColorCategory) -> Color {
        switch category {
        case .white, .beige, .yellow, .gray, .pink, .cyan:
            return .black
        default:
            return .white
        }
    }

    // MARK: - 活跃度热力图

    private var activityCard: some View {
        card(title: "穿着活跃度", subtitle: "每天的穿搭打卡频率（最近 16 周）") {
            if activity.isEmpty {
                placeholder("还没有穿搭记录")
            } else {
                ActivityHeatmapView(activity: activity)
            }
        }
    }

    // MARK: - 组件

    private func card<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    /// 颜色桶 → 代表色（用于色彩偏好图的柱子着色）。
    private func swatchColor(for category: ColorCategory) -> Color {
        switch category {
        case .black:      return .black
        case .white:      return Color(white: 0.92)
        case .gray:       return .gray
        case .beige:      return Color(red: 0.87, green: 0.82, blue: 0.70)
        case .brown:      return .brown
        case .red:        return .red
        case .orange:     return .orange
        case .yellow:     return .yellow
        case .green:      return .green
        case .cyan:       return .cyan
        case .blue:       return .blue
        case .purple:     return .purple
        case .pink:       return .pink
        case .multicolor: return Color(white: 0.6)
        }
    }
}
