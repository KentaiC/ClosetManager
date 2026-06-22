import SwiftUI
import SwiftData
import PhotosUI

/// 批量录入向导：保留全部所选图片，逐张抠图取色并打标签，「保存并下一件」推进队列直至清空。
/// 队列来源统一为 `ImageSource`——相册多选、从文件多选、拖拽释放都走这同一条流程。
struct BatchImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let queue: [ImageSource]

    @State private var index = 0
    @State private var model = ItemDraftModel()
    @State private var savedCount = 0

    private var isLast: Bool { index >= queue.count - 1 }

    var body: some View {
        NavigationStack {
            Form {
                ItemFormSections(model: model, allowsPhotoPicker: false)
            }
            .navigationTitle("批量录入")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .top) { progressBar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") { dismiss() }
                }
            }
            // index 变化时为当前图片新建模型并处理。
            .task(id: index) {
                guard index < queue.count else { return }
                let fresh = ItemDraftModel()
                model = fresh
                await fresh.process(source: queue[index])
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            Text("第 \(min(index + 1, queue.count)) / \(queue.count) 件")
                .font(.subheadline.weight(.medium))
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("跳过这张") { advance() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            Button(isLast ? "保存并完成" : "保存并下一件") {
                saveCurrent()
                advance()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!model.canSave)
        }
        .padding()
        .background(.bar)
    }

    private func saveCurrent() {
        modelContext.insert(model.makeNewItem())
        savedCount += 1
    }

    private func advance() {
        if isLast {
            dismiss()
        } else {
            index += 1
        }
    }
}
