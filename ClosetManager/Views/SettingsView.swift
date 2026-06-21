import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置页（从衣橱齿轮按钮以 Sheet 弹出）：用户画像、外观自定义、工具、数据备份。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 用户画像（@AppStorage 本地持久化）。
    @AppStorage("profile.heightCm") private var heightCm: Double = 0
    @AppStorage("profile.weightKg") private var weightKg: Double = 0
    @AppStorage("profile.age") private var age: Int = 0
    @AppStorage("profile.gender") private var genderRaw: String = Gender.unspecified.rawValue

    // 外观自定义（@AppStorage，作用于根视图）。
    @AppStorage(UIPreferenceKeys.accent) private var accentRaw = AccentChoice.purple.rawValue
    @AppStorage(UIPreferenceKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(UIPreferenceKeys.cornerRadius) private var cornerRadius = UIPreferenceKeys.defaultCornerRadius

    // 备份状态。
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showImportModeDialog = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                appearanceSection
                toolsSection
                backupSection
            }
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingImportURL = url
                    showImportModeDialog = true
                }
            }
            .confirmationDialog("导入方式", isPresented: $showImportModeDialog, titleVisibility: .visible) {
                Button("覆盖现有数据", role: .destructive) { performImport(.overwrite) }
                Button("与现有数据合并") { performImport(.merge) }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "提示",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - 个人资料

    private var profileSection: some View {
        Section {
            LabeledContent("身高") { numberField(value: $heightCm, unit: "cm") }
            LabeledContent("体重") { numberField(value: $weightKg, unit: "kg") }
            Stepper("年龄：\(age)", value: $age, in: 0...120)
            Picker("性别", selection: $genderRaw) {
                ForEach(Gender.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
        } header: {
            Text("个人资料")
        } footer: {
            Text("仅存储于本地，用于后续「衣橱补充智能建议」。")
        }
    }

    // MARK: - 外观自定义

    private var appearanceSection: some View {
        Section {
            Picker("强调色", selection: $accentRaw) {
                ForEach(AccentChoice.allCases) { choice in
                    Label {
                        Text(choice.displayName)
                    } icon: {
                        Circle().fill(choice.color).frame(width: 14, height: 14)
                    }
                    .tag(choice.rawValue)
                }
            }
            Picker("外观模式", selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("卡片圆角：\(Int(cornerRadius))")
                Slider(value: $cornerRadius, in: 0...28, step: 1)
            }
        } header: {
            Text("外观自定义")
        } footer: {
            Text("自定义不影响核心交互；强调色与外观模式即时生效。")
        }
    }

    // MARK: - 工具

    private var toolsSection: some View {
        Section("工具") {
            NavigationLink {
                TravelCapsuleView()
            } label: {
                Label("差旅打包", systemImage: "suitcase.fill")
            }
            NavigationLink {
                DuplicationView()
            } label: {
                Label("清理相似衣物", systemImage: "sparkle.magnifyingglass")
            }
        }
    }

    // MARK: - 数据备份

    private var backupSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("分享备份文件", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                exportURL = try? BackupService.exportFile(in: modelContext)
                if exportURL == nil { message = "生成备份失败。" }
            } label: {
                Label(exportURL == nil ? "生成备份文件" : "重新生成", systemImage: "externaldrive.badge.timemachine")
            }
            Button {
                showImporter = true
            } label: {
                Label("导入备份", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("数据冷备份")
        } footer: {
            Text("备份为单个 .wardrobe 文件（含图片）。先「生成」再用分享导出到文件 App / AirDrop。")
        }
    }

    // MARK: - 组件 / 逻辑

    private func numberField(value: Binding<Double>, unit: String) -> some View {
        HStack {
            TextField("0", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func performImport(_ mode: RestoreMode) {
        guard let url = pendingImportURL else { return }
        do {
            try BackupService.restore(from: url, mode: mode, in: modelContext)
            message = "导入完成。"
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
        pendingImportURL = nil
    }
}
