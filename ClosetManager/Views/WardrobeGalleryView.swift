import SwiftUI
import SwiftData

/// 衣橱主页：网格瀑布流展示所有单品，支持按分类过滤、新增与编辑。
struct WardrobeGalleryView: View {
    @Environment(\.modelContext) private var modelContext

    /// 实时读取全部单品，按创建时间倒序。
    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]

    /// 当前分类过滤；nil 表示「全部」。
    @State private var selectedCategory: Category?

    /// 编辑器路由（新增 / 编辑），用单一 sheet 承载。
    @State private var editorRoute: EditorRoute?

    /// 自适应网格列：每列最小 110pt，自动决定列数。
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    /// 按当前分类过滤后的单品。
    private var filteredItems: [ClothingItem] {
        guard let selectedCategory else { return items }
        return items.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 常驻「目前正在穿」看板。
                ActiveOutfitWidget()
                    .padding(.horizontal)
                    .padding(.top, 8)

                if items.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    categoryBar
                    gridContent
                }
            }
            .navigationTitle("我的衣橱")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorRoute = .new
                    } label: {
                        Label("添加单品", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorRoute) { route in
                switch route {
                case .new:
                    ItemEditorView()
                case .edit(let item):
                    ItemEditorView(editingItem: item)
                }
            }
        }
    }

    // MARK: - 分类导航栏

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectableChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(Category.allCases) { category in
                    SelectableChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 网格内容

    @ViewBuilder
    private var gridContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                "该分类下还没有单品",
                systemImage: "square.grid.2x2",
                description: Text("换个分类，或点击右上角 ＋ 添加。")
            )
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredItems) { item in
                    ItemCard(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editorRoute = .edit(item)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("衣橱还是空的", systemImage: "square.grid.2x2")
        } description: {
            Text("点击右上角 ＋ 添加你的第一件单品。")
        } actions: {
            Button("添加单品") { editorRoute = .new }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 操作

    private func delete(_ item: ClothingItem) {
        modelContext.delete(item)
    }
}

/// 编辑器路由：新增或编辑指定单品。
enum EditorRoute: Identifiable {
    case new
    case edit(ClothingItem)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let item):
            return item.id.uuidString
        }
    }
}
