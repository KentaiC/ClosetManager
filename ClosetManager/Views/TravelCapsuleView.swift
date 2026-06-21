import SwiftUI
import SwiftData

/// 差旅胶囊打包器：按天数与目标温度/场景生成打包建议，把单品装入行李箱（`inLuggage`）。
struct TravelCapsuleView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var allItems: [ClothingItem]

    @State private var days = 3
    @State private var warmth: WarmthLevel = .mild
    @State private var scenario: Scenario = .casual
    @State private var suggestion: [ClothingItem] = []
    @State private var toast: String?

    /// 当前已在行李箱中的单品。
    private var packedItems: [ClothingItem] {
        allItems.filter { $0.status == .inLuggage }
    }

    var body: some View {
        Form {
            tripSection
            essentialsSection
            suggestionSection
            packedSection
        }
        .navigationTitle("差旅打包")
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 行程设置

    private var tripSection: some View {
        Section("行程") {
            Stepper("旅行天数：\(days) 天", value: $days, in: 1...30)
            Picker("目标温度", selection: $warmth) {
                ForEach(WarmthLevel.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("场景", selection: $scenario) {
                ForEach(Scenario.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: - 基础携带（硬编码计算）

    private var essentialsSection: some View {
        Section {
            LabeledContent("内裤 / 打底", value: "\(TravelService.underwearCount(days: days)) 条")
            LabeledContent("袜子", value: "\(TravelService.socksCount(days: days)) 双")
        } header: {
            Text("基础携带")
        } footer: {
            if TravelService.showsCapHint(days: days) {
                Text("预计长途旅行有洗衣条件，内裤携带已封顶 \(TravelService.packingCap) 条。")
                    .foregroundStyle(.blue)
            } else {
                Text("规则：每天 1 条 + 1 条备用。")
            }
        }
    }

    // MARK: - 推荐打包

    private var suggestionSection: some View {
        Section("推荐打包") {
            Button {
                generateSuggestion()
            } label: {
                Label("按行程生成打包建议", systemImage: "suitcase")
            }

            if !suggestion.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestion) { item in
                            ItemThumbnail(item: item, size: 72)
                        }
                    }
                }
                Button {
                    packSuggestion()
                } label: {
                    Label("一键装入行李箱（\(suggestion.count) 件）", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 行李箱当前

    @ViewBuilder
    private var packedSection: some View {
        if !packedItems.isEmpty {
            Section("行李箱（\(packedItems.count) 件）") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(packedItems) { item in
                            ItemThumbnail(item: item, size: 64)
                        }
                    }
                }
                Button(role: .destructive) {
                    WearService.unpackAllLuggage(in: modelContext)
                    showToast("已结束差旅，全部取出")
                } label: {
                    Label("结束差旅，全部取出", systemImage: "arrow.uturn.left")
                }
            }
        }
    }

    // MARK: - 逻辑

    /// 生成打包建议：按行程跑 days 套穿搭，取去重后的单品集合。
    private func generateSuggestion() {
        let result = OutfitGeneratorService.generate(
            from: allItems, warmth: warmth, scenario: scenario, maxCount: days
        )
        var seen = Set<UUID>()
        var unique: [ClothingItem] = []
        for draft in result.drafts {
            for item in draft.allItems where !seen.contains(item.id) {
                seen.insert(item.id)
                unique.append(item)
            }
        }
        suggestion = unique
        if unique.isEmpty {
            showToast("可用单品不足，换个条件试试")
        }
    }

    private func packSuggestion() {
        WearService.packIntoLuggage(suggestion, in: modelContext)
        showToast("已装入行李箱")
        suggestion = []
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}
