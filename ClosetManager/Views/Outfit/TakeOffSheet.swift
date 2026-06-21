import SwiftUI
import SwiftData

/// 「脱下并扔进洗衣袋」弹窗：选择性流转。
///
/// - 智能默认：上装 / 下装 / 袜子默认勾选（贴身要洗），外套 / 鞋子 / 配饰默认不勾选。
/// - 「一键全扔」把全部单品扔进洗衣袋；「按勾选脱下」只把勾选的扔洗衣袋，其余回衣橱。
struct TakeOffSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: WearRecord

    @State private var laundrySelection: Set<ClothingItem>

    init(record: WearRecord) {
        self.record = record
        let defaults = record.items.filter { $0.category.washByDefaultOnTakeOff }
        _laundrySelection = State(initialValue: Set(defaults))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(record.items) { item in
                        row(for: item)
                    }
                } header: {
                    Text("勾选要扔进洗衣袋的单品")
                } footer: {
                    Text("未勾选的将直接回到衣橱。上装 / 下装 / 袜子已按生活常识默认勾选。")
                }
            }
            .navigationTitle("脱下穿搭")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        confirm(allToLaundry: true)
                    } label: {
                        Label("一键全扔进洗衣袋", systemImage: "washer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        confirm(allToLaundry: false)
                    } label: {
                        Text("按勾选脱下")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func row(for item: ClothingItem) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                ItemThumbnail(item: item, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? item.category.displayName : item.name)
                        .foregroundStyle(.primary)
                    Text(subtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: laundrySelection.contains(item) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(laundrySelection.contains(item) ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for item: ClothingItem) -> String {
        if let subtype = item.subtype {
            return "\(item.category.displayName) · \(subtype.displayName)"
        }
        return item.category.displayName
    }

    private func toggle(_ item: ClothingItem) {
        if laundrySelection.contains(item) {
            laundrySelection.remove(item)
        } else {
            laundrySelection.insert(item)
        }
    }

    private func confirm(allToLaundry: Bool) {
        let laundry = allToLaundry ? Set(record.items) : laundrySelection
        WearService.takeOff(record, laundryItems: laundry, in: modelContext)
        dismiss()
    }
}
