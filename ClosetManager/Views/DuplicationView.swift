import SwiftUI
import SwiftData

/// 「清理相似衣物」：手动触发的相似单品检测结果页。
///
/// 进入后在后台跑 `DuplicationDetectorService`，把相似单品按组并排展示，每件可删除。
struct DuplicationView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]

    @State private var groups: [[ClothingItem]] = []
    @State private var isRunning = false
    @State private var hasRun = false

    var body: some View {
        Group {
            if isRunning {
                ProgressView("正在分析相似度…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasRun {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "没有发现相似单品",
                    systemImage: "checkmark.seal",
                    description: Text("当前衣橱里没有颜色与款式高度相似的单品。")
                )
            } else {
                List {
                    ForEach(Array(groups.enumerated()), id: \.offset) { pair in
                        groupSection(index: pair.offset, items: pair.element)
                    }
                }
            }
        }
        .navigationTitle("清理相似衣物")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重新检测") { Task { await run() } }
                    .disabled(isRunning)
            }
        }
        .task {
            if !hasRun { await run() }
        }
    }

    private func groupSection(index: Int, items: [ClothingItem]) -> some View {
        Section("相似组 \(index + 1)（\(items.count) 件）") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        VStack(spacing: 6) {
                            ItemThumbnail(item: item, size: 96)
                            Text(item.name.isEmpty ? item.category.displayName : item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(width: 96)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 逻辑

    @MainActor
    private func run() async {
        isRunning = true
        // 在主线程准备可 Sendable 输入，再交给 actor 后台计算。
        let inputs = items.map {
            DuplicationDetectorService.ItemFingerprintInput(
                id: $0.id,
                imageData: $0.processedImageData ?? $0.originalImageData,
                color: $0.dominantColor
            )
        }
        let groupIDs = await DuplicationDetectorService.shared.findSimilarGroups(inputs)
        // 把 id 组映射回 ClothingItem。
        groups = groupIDs.map { ids in
            ids.compactMap { id in items.first { $0.id == id } }
        }
        .filter { $0.count >= 2 }
        isRunning = false
        hasRun = true
    }

    private func delete(_ item: ClothingItem) {
        modelContext.delete(item)
        // 从当前展示的组里移除，组内不足 2 件则整组移除。
        groups = groups
            .map { $0.filter { $0.id != item.id } }
            .filter { $0.count >= 2 }
    }
}
