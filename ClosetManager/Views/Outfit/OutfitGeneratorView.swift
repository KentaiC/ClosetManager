import SwiftUI
import SwiftData

/// 智能穿搭生成：选「保暖/体感 + 场景」→ 生成多套 → 横滑卡片浏览并操作。
struct OutfitGeneratorView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var allItems: [ClothingItem]

    @State private var warmth: WarmthLevel = .mild
    @State private var scenario: Scenario = .casual
    @State private var requireWaterproof = false
    @State private var result: OutfitGeneratorService.Result?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                conditionPanel
                generateButton
                resultsArea
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 条件面板

    private var conditionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("保暖 / 体感").font(.subheadline.weight(.medium))
                FlowLayout(spacing: 8) {
                    ForEach(WarmthLevel.allCases) { level in
                        SelectableChip(
                            title: level.displayName,
                            systemImage: level.symbolName,
                            isSelected: warmth == level
                        ) { warmth = level }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("场景").font(.subheadline.weight(.medium))
                FlowLayout(spacing: 8) {
                    ForEach(Scenario.allCases) { item in
                        SelectableChip(
                            title: item.displayName,
                            isSelected: scenario == item
                        ) { scenario = item }
                    }
                }
            }
            // 雨雪天气强关联：开启后强制外套与鞋子防水。
            Toggle(isOn: $requireWaterproof) {
                Label("雨 / 雪天（强制防水外套与鞋子）", systemImage: "cloud.rain")
            }
            .font(.subheadline)
        }
    }

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            Label("生成穿搭", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultsArea: some View {
        if let result {
            if !result.missingRequired.isEmpty {
                missingView(result.missingRequired)
            } else if result.drafts.isEmpty {
                emptyResultView
            } else {
                TabView {
                    ForEach(result.drafts) { draft in
                        OutfitDraftCard(
                            draft: draft,
                            onFavorite: { favorite(draft) },
                            onWear: { wear(draft) }
                        )
                        .padding(.horizontal, 4)
                        .padding(.bottom, 40)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 420)
            }
        } else {
            Text("选择上方条件后点「生成穿搭」。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        }
    }

    private func missingView(_ missing: [Category]) -> some View {
        ContentUnavailableView(
            "缺少必选单品，无法生成",
            systemImage: "exclamationmark.triangle",
            description: Text("当前条件下缺少：\(missing.map(\.displayName).joined(separator: "、"))。请先在衣橱补充对应单品。")
        )
        .padding(.top, 20)
    }

    private var emptyResultView: some View {
        ContentUnavailableView(
            "没有匹配的穿搭",
            systemImage: "questionmark.square.dashed",
            description: Text("没有同时满足该温度与场景的组合，换个条件试试。")
        )
        .padding(.top, 20)
    }

    // MARK: - 操作

    private func generate() {
        result = OutfitGeneratorService.generate(
            from: allItems,
            warmth: warmth,
            scenario: scenario,
            requireWaterproof: requireWaterproof
        )
    }

    private func favorite(_ draft: OutfitDraft) {
        WearService.addToFavorites(draft, scenario: scenario, warmth: warmth, in: modelContext)
        showToast("已加入收藏")
    }

    private func wear(_ draft: OutfitDraft) {
        WearService.wearToday(draft, in: modelContext)
        showToast("已设为今天穿这套")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}
