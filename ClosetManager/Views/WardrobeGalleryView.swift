import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

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

    /// 批量录入（相册多选 / 文件多选 / 拖拽，统一汇入 batchSources）。
    @State private var showBatchPicker = false
    @State private var showBatchFileImporter = false
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var batchSources: [ImageSource] = []
    @State private var showBatchEditor = false
    /// 拖拽悬停高亮。
    @State private var isDropTargeted = false

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
            // 拖拽释放：从 Finder / 网页 / 其他 App 拖入图片 → 捕获 Data → 触发批量编辑向导。
            .dropDestination(for: Data.self) { datas, _ in
                guard !datas.isEmpty else { return false }
                startBatch(with: datas.map(ImageSource.data))
                return true
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(8)
                        .allowsHitTesting(false)
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
            .sheet(isPresented: $showBatchEditor, onDismiss: { batchSources = []; batchItems = [] }) {
                BatchImportView(queue: batchSources)
            }
            .photosPicker(
                isPresented: $showBatchPicker,
                selection: $batchItems,
                maxSelectionCount: 30,
                matching: .images
            )
            .onChange(of: batchItems) { _, newItems in
                // 相册多选 → 转为统一来源并进入批量编辑。
                if !newItems.isEmpty { startBatch(with: newItems.map(ImageSource.photo)) }
            }
            .fileImporter(
                isPresented: $showBatchFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                handleBatchFileImport(result)
            }
        }
    }

    /// 进入批量编辑向导。
    private func startBatch(with sources: [ImageSource]) {
        guard !sources.isEmpty else { return }
        batchSources = sources
        showBatchEditor = true
    }

    /// 从文件多选导入：逐个 URL 在安全沙盒内读取为 Data，再汇入批量编辑。
    private func handleBatchFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var datas: [Data] = []
        for url in urls {
            // 关键：iCloud Drive 等外部文件 URL 受沙盒保护，必须先申请权限再读取，读完释放，否则会权限崩溃。
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { datas.append(data) }
        }
        startBatch(with: datas.map(ImageSource.data))
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
                    Label("从相册批量录入", systemImage: "photo.on.rectangle")
                }
                Button { showBatchFileImporter = true } label: {
                    Label("从文件批量录入", systemImage: "folder")
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
