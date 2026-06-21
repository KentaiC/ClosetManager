import SwiftUI
import SwiftData

/// 添加 / 编辑单品表单（单件）。
///
/// 表单内容复用 `ItemFormSections` + `ItemDraftModel`，逻辑集中在模型层。
/// `editingItem == nil` 为新增，否则为编辑。
///
/// 权限说明：`PhotosPicker` 基于系统 PHPicker，在独立进程运行，
/// 仅选取图片不会触发相册权限弹窗，也无需配置 `NSPhotoLibraryUsageDescription`。
struct ItemEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let editingItem: ClothingItem?
    @State private var model: ItemDraftModel

    init(editingItem: ClothingItem? = nil) {
        self.editingItem = editingItem
        _model = State(initialValue: editingItem.map { ItemDraftModel(editing: $0) } ?? ItemDraftModel())
    }

    var body: some View {
        NavigationStack {
            Form {
                ItemFormSections(model: model)
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
                        .disabled(!model.canSave)
                }
            }
        }
    }

    private func save() {
        if let editingItem {
            model.apply(to: editingItem)
        } else {
            modelContext.insert(model.makeNewItem())
        }
        dismiss()
    }
}
