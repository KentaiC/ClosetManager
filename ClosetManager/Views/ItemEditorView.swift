import SwiftUI
import SwiftData
import PhotosUI

/// 添加 / 编辑单品表单。
///
/// - `editingItem == nil` 时为「新增」模式；非 nil 时为「编辑」模式。
/// - 顶部 `PhotosPicker` 选图后，调用 `VisionService` 本地抠图 + CoreImage 取色，实时预览。
/// - 名称默认按「颜色 + 子类」自动生成（如「绿色短裤」）；只要用户没手动填名称，
///   它会随分类 / 子类 / 取色结果实时更新；用户一旦输入即视为自定义，清空后恢复自动。
/// - 鞋子 / 配饰默认不进洗衣袋（状态锁定在衣橱）。
///
/// 权限说明：`PhotosPicker` 基于系统 PHPicker，在独立进程中运行，
/// **用户仅选取单张图片不会触发相册权限弹窗，也无需在 Info.plist 配置
/// `NSPhotoLibraryUsageDescription`**，这是相比传统 UIImagePickerController 的关键优势。
struct ItemEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 待编辑单品；为 nil 表示新增。
    private let editingItem: ClothingItem?

    // MARK: - 表单状态

    /// 用户手动输入的名称（仅当 `nameManuallyEdited == true` 时生效）。
    @State private var customName: String
    /// 名称是否已被用户手动编辑（false 时使用自动生成的 `defaultName`）。
    @State private var nameManuallyEdited: Bool

    @State private var category: Category
    @State private var subtype: Subtype?
    @State private var selectedScenarios: Set<Scenario>
    @State private var selectedWarmthLevels: Set<WarmthLevel>
    @State private var selectedSeasons: Set<Season>
    @State private var status: ItemStatus
    @State private var brand: String
    @State private var notes: String

    // MARK: - 图像 / 颜色状态

    @State private var originalImageData: Data?
    @State private var processedImageData: Data?
    @State private var dominantColor: StoredColor
    @State private var secondaryColor: StoredColor?
    @State private var pickerItem: PhotosPickerItem?
    @State private var processingState: ProcessingState = .idle

    /// 季节是否已被用户手动编辑（true 后不再随保暖标签自动覆盖）。
    @State private var seasonsManuallyEdited: Bool

    /// 抠图处理状态。
    private enum ProcessingState: Equatable {
        case idle
        case processing
        case success
        case failed(String)
    }

    init(editingItem: ClothingItem? = nil) {
        self.editingItem = editingItem
        _customName = State(initialValue: editingItem?.name ?? "")
        _nameManuallyEdited = State(initialValue: !(editingItem?.name.isEmpty ?? true))
        _category = State(initialValue: editingItem?.category ?? .top)
        _subtype = State(initialValue: editingItem?.subtype)
        _selectedScenarios = State(initialValue: Set(editingItem?.scenarios ?? []))
        _selectedWarmthLevels = State(initialValue: Set(editingItem?.warmthLevels ?? []))
        _selectedSeasons = State(initialValue: Set(editingItem?.seasons ?? []))
        _status = State(initialValue: editingItem?.status ?? .inWardrobe)
        _brand = State(initialValue: editingItem?.brand ?? "")
        _notes = State(initialValue: editingItem?.notes ?? "")
        _originalImageData = State(initialValue: editingItem?.originalImageData)
        _processedImageData = State(initialValue: editingItem?.processedImageData)
        _dominantColor = State(initialValue: editingItem?.dominantColor ?? StoredColor(red: 0.5, green: 0.5, blue: 0.5))
        _secondaryColor = State(initialValue: editingItem?.secondaryColor)
        // 已有季节数据视为「手动」，避免编辑时被保暖标签自动覆盖。
        _seasonsManuallyEdited = State(initialValue: !(editingItem?.seasons.isEmpty ?? true))
    }

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                basicInfoSection
                colorSection
                scenarioSection
                warmthSection
                seasonSection
                statusSection
                extraSection
            }
            .navigationTitle(editingItem == nil ? "新增单品" : "编辑单品")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadAndProcess(newItem) }
            }
            .onChange(of: selectedWarmthLevels) { _, _ in
                deriveSeasonsIfNeeded()
            }
            .onChange(of: category) { _, newCategory in
                // 切换分类后：子类不匹配则清空。
                if let current = subtype, current.category != newCategory {
                    subtype = nil
                }
            }
        }
    }

    // MARK: - 名称（自动 / 手动）

    /// 自动生成的默认名称：颜色 + 子类（如「绿色短裤」）。
    private var defaultName: String {
        ClothingItem.defaultName(color: dominantColor, subtype: subtype, category: category)
    }

    /// 名称输入框绑定：未手动编辑时显示并随状态实时更新默认名；输入即转自定义；清空则恢复自动。
    private var nameBinding: Binding<String> {
        Binding(
            get: { nameManuallyEdited ? customName : defaultName },
            set: { newValue in
                if newValue.isEmpty {
                    customName = ""
                    nameManuallyEdited = false
                } else {
                    customName = newValue
                    nameManuallyEdited = true
                }
            }
        )
    }

    // MARK: - 图片区（PhotosPicker + 去背预览）

    @ViewBuilder
    private var imageSection: some View {
        Section {
            VStack(spacing: 12) {
                previewArea
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(displayImageData == nil ? "从相册选择图片" : "更换图片",
                          systemImage: "photo.on.rectangle.angled")
                }
                .disabled(processingState == .processing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } footer: {
            if case .failed(let message) = processingState {
                Text(message)
                    .foregroundStyle(.orange)
            } else if processedImageData == nil && originalImageData != nil {
                Text("已使用原图（未识别到主体或尚未完成去背）。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 当前用于预览的图片数据：优先去背结果，回退原图。
    private var displayImageData: Data? {
        processedImageData ?? originalImageData
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary.opacity(0.4))
                .frame(height: 240)

            switch processingState {
            case .processing:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在本地抠图…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            default:
                if let data = displayImageData, let image = Image(platformData: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text("尚未选择图片")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 基本信息

    private var basicInfoSection: some View {
        Section {
            TextField("名称", text: nameBinding, prompt: Text(defaultName))

            Picker("分类", selection: $category) {
                ForEach(Category.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }

            Picker("子类", selection: $subtype) {
                Text("未指定").tag(Subtype?.none)
                ForEach(category.subtypes) { sub in
                    Text(sub.displayName).tag(Subtype?.some(sub))
                }
            }
        } header: {
            Text("基本信息")
        } footer: {
            if !nameManuallyEdited {
                Text("名称已按「颜色 + 子类」自动生成，可直接修改。")
            }
        }
    }

    // MARK: - 颜色（自动提取）

    @ViewBuilder
    private var colorSection: some View {
        if displayImageData != nil {
            Section("颜色（自动提取）") {
                HStack(spacing: 24) {
                    colorSwatch(title: "主色", color: dominantColor)
                    if let secondaryColor {
                        colorSwatch(title: "辅色", color: secondaryColor)
                    }
                }
            }
        }
    }

    private func colorSwatch(title: String, color: StoredColor) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.color)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(ColorCategory.classify(color).displayName).font(.subheadline)
            }
        }
    }

    // MARK: - 适用场景

    @ViewBuilder
    private var scenarioSection: some View {
        Section {
            ChipMultiSelect(
                options: Scenario.allCases,
                title: { $0.displayName },
                selection: $selectedScenarios
            )
        } header: {
            Text("适用场景")
        } footer: {
            if hasScenarioConflict {
                Text("「正式」与「运动」相互冲突，建议不要同时选择。")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var hasScenarioConflict: Bool {
        selectedScenarios.contains {
            !$0.conflictingScenarios.isDisjoint(with: selectedScenarios)
        }
    }

    // MARK: - 保暖程度

    private var warmthSection: some View {
        Section {
            ChipMultiSelect(
                options: WarmthLevel.allCases,
                title: { $0.displayName },
                systemImage: { $0.symbolName },
                selection: $selectedWarmthLevels
            )
        } header: {
            Text("保暖程度（当前天气）")
        } footer: {
            Text("可多选。穿搭引擎会据此匹配当前天气下可穿的单品。")
        }
    }

    // MARK: - 适用季节

    private var seasonSection: some View {
        Section {
            ChipMultiSelect(
                options: Season.allCases,
                title: { $0.displayName },
                systemImage: { $0.symbolName },
                selection: $selectedSeasons,
                onToggle: { seasonsManuallyEdited = true }
            )
            if seasonsManuallyEdited {
                Button("恢复为按保暖程度自动匹配") {
                    seasonsManuallyEdited = false
                    deriveSeasonsIfNeeded()
                }
                .font(.footnote)
            }
        } header: {
            Text("适用季节")
        } footer: {
            Text(seasonsManuallyEdited
                 ? "已手动调整季节。"
                 : "默认由保暖程度自动推导，可手动调整。")
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            Picker("当前状态", selection: $status) {
                ForEach(ItemStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("状态")
        } footer: {
            Text("一般通过「脱下穿搭」自动流转；此处可手动调整。")
        }
    }

    // MARK: - 其它

    private var extraSection: some View {
        Section("其它（可选）") {
            TextField("品牌", text: $brand)
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    // MARK: - 逻辑

    /// 是否允许保存：至少有一张图片，且未在抠图处理中。
    private var canSave: Bool {
        displayImageData != nil && processingState != .processing
    }

    /// 加载所选图片并执行本地抠图 + 取色。
    @MainActor
    private func loadAndProcess(_ item: PhotosPickerItem) async {
        processingState = .processing
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                processingState = .failed("无法读取所选图片。")
                return
            }
            originalImageData = data
            // 调用本地 Vision 抠图服务（actor 自动在后台执行）。
            let processed = try await VisionService.shared.removeBackground(from: data)
            processedImageData = processed
            // 在透明背景图上取色，避免背景干扰。
            await extractColors(from: processed)
            processingState = .success
        } catch {
            // 抠图失败：保留原图作为预览，并在原图上取色（仍可保存）。
            processedImageData = nil
            if let original = originalImageData {
                await extractColors(from: original)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            processingState = .failed(message)
        }
    }

    /// 提取主辅色并写入状态（未手动改名时，默认名会随之实时更新）。
    private func extractColors(from data: Data) async {
        let colors = await VisionService.shared.extractColors(from: data)
        dominantColor = colors.dominant
        secondaryColor = colors.secondary
    }

    /// 若季节未被手动编辑，则依据保暖标签自动推导。
    private func deriveSeasonsIfNeeded() {
        guard !seasonsManuallyEdited else { return }
        let levels = WarmthLevel.allCases.filter { selectedWarmthLevels.contains($0) }
        selectedSeasons = Set(Season.derive(from: levels))
    }

    /// 保存：写入新单品或更新既有单品。
    private func save() {
        let scenarioArray = Scenario.allCases.filter { selectedScenarios.contains($0) }
        let warmthArray = WarmthLevel.allCases.filter { selectedWarmthLevels.contains($0) }
        let seasonArray = Season.allCases.filter { selectedSeasons.contains($0) }
        let finalName = nameManuallyEdited ? customName : defaultName

        if let item = editingItem {
            // 编辑：原地更新。
            item.name = finalName
            item.category = category
            item.subtype = subtype
            item.scenarios = scenarioArray
            item.warmthLevels = warmthArray
            item.seasons = seasonArray
            item.status = status
            item.brand = brand.isEmpty ? nil : brand
            item.notes = notes.isEmpty ? nil : notes
            item.originalImageData = originalImageData
            item.processedImageData = processedImageData
            item.dominantColor = dominantColor
            item.secondaryColor = secondaryColor
            item.refreshColorCategory()
            item.updatedAt = .now
        } else {
            // 新增：构造并插入。
            let newItem = ClothingItem(
                name: finalName,
                category: category,
                subtype: subtype,
                scenarios: scenarioArray,
                status: status,
                processedImageData: processedImageData,
                originalImageData: originalImageData,
                dominantColor: dominantColor,
                secondaryColor: secondaryColor,
                warmthLevels: warmthArray,
                seasons: seasonArray,
                brand: brand.isEmpty ? nil : brand,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(newItem)
        }
        dismiss()
    }
}
