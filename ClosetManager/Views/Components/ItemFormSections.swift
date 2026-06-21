import SwiftUI
import PhotosUI

/// 可复用的单品录入表单区块（绑定 `ItemDraftModel`）。
///
/// 放进父级的 `Form { }` 中使用。单件编辑显示相册选择器；批量录入由队列预置图片，
/// 用 `allowsPhotoPicker: false` 隐藏选择器。
struct ItemFormSections: View {
    @Bindable var model: ItemDraftModel
    var allowsPhotoPicker: Bool = true

    @State private var pickerItem: PhotosPickerItem?
    /// 用于把 ColorPicker 选中的 Color 解析为 sRGB 分量。
    @Environment(\.self) private var environment

    var body: some View {
        Group {
            imageSection
            basicInfoSection
            colorSection
            scenarioSection
            warmthSection
            seasonSection
            statusSection
            extraSection
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await model.process(newItem) }
        }
        .onChange(of: model.warmthScore) { _, _ in
            model.deriveSeasonsIfNeeded()
        }
        .onChange(of: model.category) { _, _ in
            model.reconcileSubtype()
        }
    }

    // MARK: - 名称绑定

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.nameManuallyEdited ? model.customName : model.defaultName },
            set: { newValue in
                if newValue.isEmpty {
                    model.customName = ""
                    model.nameManuallyEdited = false
                } else {
                    model.customName = newValue
                    model.nameManuallyEdited = true
                }
            }
        )
    }

    // MARK: - 图片区

    @ViewBuilder
    private var imageSection: some View {
        Section {
            VStack(spacing: 12) {
                previewArea
                if allowsPhotoPicker {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(model.displayImageData == nil ? "从相册选择图片" : "更换图片",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(model.processingState == .processing)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } footer: {
            if case .failed(let message) = model.processingState {
                Text(message).foregroundStyle(.orange)
            } else if model.processedImageData == nil && model.originalImageData != nil {
                Text("已使用原图（未识别到主体或尚未完成去背）。").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary.opacity(0.4))
                .frame(height: 240)

            switch model.processingState {
            case .processing:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在本地抠图…").font(.footnote).foregroundStyle(.secondary)
                }
            default:
                if let data = model.displayImageData, let image = Image(platformData: data) {
                    image.resizable().scaledToFit().padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tshirt").font(.system(size: 44)).foregroundStyle(.tertiary)
                        Text("尚未选择图片").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 基本信息

    private var basicInfoSection: some View {
        Section {
            TextField("名称", text: nameBinding, prompt: Text(model.defaultName))

            Picker("分类", selection: $model.category) {
                ForEach(Category.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }

            Picker("子类", selection: $model.subtype) {
                Text("未指定").tag(Subtype?.none)
                ForEach(model.category.subtypes) { sub in
                    Text(sub.displayName).tag(Subtype?.some(sub))
                }
            }
        } header: {
            Text("基本信息")
        } footer: {
            if !model.nameManuallyEdited {
                Text("名称已按「颜色 + 子类」自动生成，可直接修改。")
            }
        }
    }

    // MARK: - 颜色

    @ViewBuilder
    private var colorSection: some View {
        if model.displayImageData != nil {
            Section {
                HStack(spacing: 24) {
                    colorSwatch(title: "主色", color: model.dominantColor)
                    if let secondaryColor = model.secondaryColor {
                        colorSwatch(title: "辅色", color: secondaryColor)
                    }
                }
                // 吸管 / 自定义：不满意自动取色时手动调整（系统色板含屏幕吸管）。
                ColorPicker("自定义主色（可吸管取色）", selection: dominantColorBinding, supportsOpacity: false)
            } header: {
                Text("颜色")
            } footer: {
                Text("自动提取主辅色；可点右侧色块手动调整，或用系统吸管从图片精确取色。")
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
                Text(color.refinedColorName).font(.subheadline)
            }
        }
    }

    /// 主色的 Color 绑定：读取 StoredColor → Color；写回时把 Color 解析为 sRGB 分量。
    private var dominantColorBinding: Binding<Color> {
        Binding(
            get: { model.dominantColor.color },
            set: { newColor in
                let resolved = newColor.resolve(in: environment)
                model.dominantColor = StoredColor(
                    red: Double(resolved.red),
                    green: Double(resolved.green),
                    blue: Double(resolved.blue),
                    alpha: Double(resolved.opacity)
                )
            }
        )
    }

    // MARK: - 场景

    @ViewBuilder
    private var scenarioSection: some View {
        Section {
            ChipMultiSelect(
                options: Scenario.allCases,
                title: { $0.displayName },
                selection: $model.selectedScenarios
            )
        } header: {
            Text("适用场景")
        } footer: {
            if hasScenarioConflict {
                Text("「正式」与「运动」相互冲突，建议不要同时选择。").foregroundStyle(.orange)
            }
        }
    }

    private var hasScenarioConflict: Bool {
        model.selectedScenarios.contains {
            !$0.conflictingScenarios.isDisjoint(with: model.selectedScenarios)
        }
    }

    // MARK: - 保暖

    private var warmthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("保暖度 \(model.warmthScore)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Label(model.warmthLevel.displayName, systemImage: model.warmthLevel.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(model.warmthScore) },
                        set: { model.warmthScore = Int($0.rounded()) }
                    ),
                    in: 1...100,
                    step: 1
                )
            }
        } header: {
            Text("保暖度")
        } footer: {
            Text("1 最薄（短袖）→ 100 最厚（羽绒）。叠穿算法据此做「保暖度求和匹配气温」。")
        }
    }

    // MARK: - 季节

    private var seasonSection: some View {
        Section {
            ChipMultiSelect(
                options: Season.allCases,
                title: { $0.displayName },
                systemImage: { $0.symbolName },
                selection: $model.selectedSeasons,
                onToggle: { model.seasonsManuallyEdited = true }
            )
            if model.seasonsManuallyEdited {
                Button("恢复为按保暖程度自动匹配") {
                    model.seasonsManuallyEdited = false
                    model.deriveSeasonsIfNeeded()
                }
                .font(.footnote)
            }
        } header: {
            Text("适用季节")
        } footer: {
            Text(model.seasonsManuallyEdited ? "已手动调整季节。" : "默认由保暖程度自动推导，可手动调整。")
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            Picker("当前状态", selection: $model.status) {
                ForEach(ItemStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)

            // 防水开关：对所有分类（含内衣裤、鞋袜配饰）都提供。
            Toggle(isOn: $model.isWaterproof) {
                Label("防水 / 防泼水", systemImage: "umbrella.fill")
            }
        } header: {
            Text("状态")
        } footer: {
            Text("一般通过「脱下穿搭」自动流转；防水属性供雨雪天气穿搭强关联使用。")
        }
    }

    // MARK: - 其它

    private var extraSection: some View {
        Section("其它（可选）") {
            TextField("品牌", text: $model.brand)
            TextField("备注", text: $model.notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
