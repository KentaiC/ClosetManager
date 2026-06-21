import SwiftUI
import SwiftData

/// 高阶条件查询：多维度交叉筛选（场景 / 防水 / 主色 / 过去 90 天未穿），结果瀑布流展示。
struct WardrobeSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]

    @State private var scenario: Scenario?
    @State private var waterproofOnly = false
    @State private var color: ColorCategory?
    @State private var unwornOnly = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    /// 90 天未穿的判定基准。
    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
    }

    private var results: [ClothingItem] {
        items.filter { item in
            (scenario == nil || item.scenarios.contains(scenario!))
            && (!waterproofOnly || item.isWaterproof)
            && (color == nil || item.dominantColorCategory == color!)
            && (!unwornOnly || !item.wearRecords.contains { $0.date >= cutoff })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                filterPanel
                resultsHeader
                if results.isEmpty {
                    ContentUnavailableView(
                        "没有符合条件的单品",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("放宽筛选条件试试。")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { item in
                            ItemCard(item: item)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("高级筛选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("重置") { reset() }
                }
            }
        }
    }

    // MARK: - 筛选面板

    private var filterPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("场景")
                Spacer()
                Menu(scenario?.displayName ?? "全部") {
                    Button("全部") { scenario = nil }
                    ForEach(Scenario.allCases) { s in
                        Button(s.displayName) { scenario = s }
                    }
                }
            }
            Divider()
            HStack {
                Text("主色")
                Spacer()
                Menu(color?.displayName ?? "全部") {
                    Button("全部") { color = nil }
                    ForEach(ColorCategory.allCases) { c in
                        Button(c.displayName) { color = c }
                    }
                }
            }
            Divider()
            Toggle("仅防水单品", isOn: $waterproofOnly)
            Divider()
            Toggle("过去 90 天未穿过（吃灰单品）", isOn: $unwornOnly)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .padding([.horizontal, .top])
    }

    private var resultsHeader: some View {
        Text("共 \(results.count) 件")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 4)
    }

    private func reset() {
        scenario = nil
        color = nil
        waterproofOnly = false
        unwornOnly = false
    }
}
