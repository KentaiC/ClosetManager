import SwiftUI
import SwiftData
import PhotosUI

/// 衣橱主页：网格展示单品，支持分类过滤、洗衣袋隔离、视图大小切换、单件/批量录入与设置入口。
struct WardrobeGalleryView: View {
    @Environment(\.modelContext) private var modelContext

    /// 实时读取全部单品，按创建时间倒序。
    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]

    /// 当前分类过滤；nil 表示「全部」。
    @State private var selectedCategory: Category?

    /// 是否显示洗衣袋内衣物（默认隐藏）。
    @State private var showLaundry = false

    /// 视图大小（@AppStorage 持久化）。
    @AppStorage("galleryItemSize") private var sizeRaw = GalleryItemSize.medium.rawValue
    private var size: GalleryItemSize { GalleryItemSize(rawValue: sizeRaw) ?? .medium }

    /// 编辑器路由（新增 / 编辑），用单一 sheet 承载。
    @State private var editorRoute: EditorRoute?

    /// 设置页。
    @State private var showSettings = false

    /// 批量录入。
    @State private var showBatchPicker = false
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var showBatchEditor = false

    /// 高级筛选页开关。
    @State private var showSearch = false

    /// 按「洗衣袋/行李箱隔离 + 分类」过滤后的单品。
    /// 行李箱(`inLuggage`)始终隔离；洗衣袋(`inLaundry`)仅在开关开启时显示。
    private var filteredItems: [ClothingItem] {
        items
            .filter { item in
                switch item.status {
                case .inWardrobe: return true
                case .inLaundry:  return showLaundry
                case .inLuggage:  return false
                }
            }
            .filter { selectedCategory == nil || $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 常驻「目前正在穿」看板。
                ActiveOutfitWidget()
                    .padding(.horizontal)
                    .padding(.top, 8)

                if showLaundry {
                    laundryNotice
                }

                if items.isEmpty {
                    emptyState.padding(.top, 40)
                } else {
                    categoryBar
                    gridContent
                }
            }
            .navigationTitle("我的衣橱")
            .toolbar { toolbarContent }
            .sheet(item: $editorRoute) { route in
                switch route {
                case .new:  ItemEditorView()
                case .edit(let item): ItemEditorView(editingItem: item)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showSearch) {
                WardrobeSearchView()
            }
            .sheet(isPresented: $showBatchEditor, onDismiss: { batchItems = [] }) {
                BatchImportView(queue: batchItems)
            }
            .photosPicker(
                isPresented: $showBatchPicker,
                selection: $batchItems,
                maxSelectionCount: 30,
                matching: .images
            )
            .onChange(of: batchItems) { _, newItems in
                if !newItems.isEmpty { showBatchEditor = true }
            }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { showSearch = true } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("视图大小", selection: $sizeRaw) {
                    ForEach(GalleryItemSize.allCases) { size in
                        Label(size.displayName, systemImage: size.symbolName).tag(size.rawValue)
                    }
                }
                Toggle("显示洗衣袋内衣物", isOn: $showLaundry)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { editorRoute = .new } label: {
                    Label("单件录入", systemImage: "plus")
                }
                Button { showBatchPicker = true } label: {
                    Label("批量录入", systemImage: "square.stack.3d.up")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - 洗衣袋提示条

    private var laundryNotice: some View {
        Label("正在显示洗衣袋内衣物", systemImage: "drop.fill")
            .font(.caption)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
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
                "该分类下没有可显示的单品",
                systemImage: "square.grid.2x2",
                description: Text("换个分类，或在右上角 ＋ 添加。")
            )
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: size.columns, spacing: size.spacing) {
                ForEach(filteredItems) { item in
                    ItemCard(item: item, compact: !size.showsLabels)
                        .contentShape(Rectangle())
                        .onTapGesture { editorRoute = .edit(item) }
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
