import SwiftUI
import SwiftData
import PhotosUI

/// 添加 / 编辑单品表单。
///
/// - `editingItem == nil` 时为「新增」模式；非 nil 时为「编辑」模式。
/// - 顶部 `PhotosPicker` 选图后，调用 `VisionService` 本地抠图并实时预览去背结果。
/// - 表单区用原生 `Form` 承载各项枚举属性（分类 / 场景 / 保暖 / 季节 / 状态）。
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

    @State private var name: String
    @State private var category: Category
    @State private var selectedScenarios: Set<Scenario>
    @State private var selectedWarmthLevels: Set<WarmthLevel>
    @State private var selectedSeasons: Set<Season>
    @State private var status: ItemStatus
    @State private var brand: String
    @State private var notes: String

    // MARK: - 图像状态

    @State private var originalImageData: Data?
    @State private var processedImageData: Data?
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
        _name = State(initialValue: editingItem?.name ?? "")
        _category = State(initialValue: editingItem?.category ?? .top)
        _selectedScenarios = State(initialValue: Set(editingItem?.scenarios ?? []))
        _selectedWarmthLevels = State(initialValue: Set(editingItem?.warmthLevels ?? []))
        _selectedSeasons = State(initialValue: Set(editingItem?.seasons ?? []))
        _status = State(initialValue: editingItem?.status ?? .inWardrobe)
        _brand = State(initialValue: editingItem?.brand ?? "")
        _notes = State(initialValue: editingItem?.notes ?? "")
        _originalImageData = State(initialValue: editingItem?.originalImageData)
        _processedImageData = State(initialValue: editingItem?.processedImageData)
        // 已有季节数据视为「手动」，避免编辑时被保暖标签自动覆盖。
        _seasonsManuallyEdited = State(initialValue: !(editingItem?.seasons.isEmpty ?? true))
    }

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                basicInfoSection
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
        }
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
        Section("基本信息") {
            TextField("名称（如：白色基础款 T 恤）", text: $name)

            Picker("分类", selection: $category) {
                ForEach(Category.allCases) { category in
                    Text(category.displayName).tag(category)
                }
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
        Section("状态") {
            Picker("当前状态", selection: $status) {
                ForEach(ItemStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
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

    /// 加载所选图片并执行本地抠图。
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
            processingState = .success
        } catch {
            // 抠图失败：保留原图作为预览，提示用户（仍可保存）。
            processedImageData = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            processingState = .failed(message)
        }
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

        if let item = editingItem {
            // 编辑：原地更新。
            item.name = name
            item.category = category
            item.scenarios = scenarioArray
            item.warmthLevels = warmthArray
            item.seasons = seasonArray
            item.status = status
            item.brand = brand.isEmpty ? nil : brand
            item.notes = notes.isEmpty ? nil : notes
            item.originalImageData = originalImageData
            item.processedImageData = processedImageData
            item.updatedAt = .now
        } else {
            // 新增：构造并插入。dominantColor 暂用默认占位，阶段三由 CoreImage 覆盖。
            let newItem = ClothingItem(
                name: name,
                category: category,
                scenarios: scenarioArray,
                status: status,
                processedImageData: processedImageData,
                originalImageData: originalImageData,
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
