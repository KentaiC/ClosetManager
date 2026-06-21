import SwiftUI
import SwiftData

/// 洗衣房：筛选所有「在洗衣袋」的单品，支持勾选（全部 / 部分）后一键「洗净放回」衣橱。
struct LaundryView: View {
    @Environment(\.modelContext) private var modelContext

    /// 读取全部单品后在内存中筛选（避免对自定义枚举做谓词过滤）。
    @Query(sort: \ClothingItem.updatedAt, order: .reverse)
    private var allItems: [ClothingItem]

    /// 已勾选待放回的单品 id。
    @State private var selection: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    private var laundryItems: [ClothingItem] {
        allItems.filter { $0.status == .inLaundry }
    }

    private var allSelected: Bool {
        !laundryItems.isEmpty && selection.count == laundryItems.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if laundryItems.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("洗衣房")
            .toolbar {
                if !laundryItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(allSelected ? "全不选" : "全选") {
                            selection = allSelected ? [] : Set(laundryItems.map(\.id))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !laundryItems.isEmpty {
                    Button {
                        washSelected()
                    } label: {
                        Label("洗净放回（\(selection.count)）", systemImage: "arrow.uturn.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selection.isEmpty)
                    .padding()
                    .background(.bar)
                }
            }
            // 列表变化时清掉已不存在的选中项。
            .onChange(of: laundryItems.map(\.id)) { _, ids in
                selection = selection.intersection(ids)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(laundryItems) { item in
                    ItemCard(item: item)
                        .overlay(alignment: .topLeading) {
                            selectionBadge(isSelected: selection.contains(item.id))
                                .padding(6)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(selection.contains(item.id) ? Color.accentColor : .clear, lineWidth: 3)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(item) }
                }
            }
            .padding()
        }
    }

    private func selectionBadge(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .imageScale(.large)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(Circle().fill(.background))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("洗衣袋是空的", systemImage: "washer")
        } description: {
            Text("被标记为「在洗衣袋」的单品会出现在这里。")
        }
    }

    private func toggle(_ item: ClothingItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func washSelected() {
        let chosen = laundryItems.filter { selection.contains($0.id) }
        WearService.returnToWardrobe(chosen, in: modelContext)
        selection.removeAll()
    }
}
