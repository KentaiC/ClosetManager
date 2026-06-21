import SwiftUI
import SwiftData

/// 自由拼搭：从衣橱中手动为每个槽位挑选单品，组成一套 Outfit。
///
/// 约束：上装 / 下装 / 鞋子必选；外套 / 袜子 / 配饰可选。集齐必选项后才能收藏 / 穿着。
struct ManualOutfitBuilderView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ClothingItem.createdAt, order: .reverse)
    private var allItems: [ClothingItem]

    @State private var picked: [Category: ClothingItem] = [:]
    @State private var toast: String?

    /// 槽位定义：分类 + 是否必选。
    private let slots: [(category: Category, required: Bool)] = [
        (.outerwear, false),
        (.top, true),
        (.bottom, true),
        (.socks, false),
        (.shoes, true),
        (.accessory, false)
    ]

    private func candidates(for category: Category) -> [ClothingItem] {
        allItems.filter { $0.isAvailable && $0.category == category }
    }

    /// 已集齐必选项。
    private var isComplete: Bool {
        picked[.top] != nil && picked[.bottom] != nil && picked[.shoes] != nil
    }

    private var draft: OutfitDraft? {
        guard let top = picked[.top], let bottom = picked[.bottom], let shoes = picked[.shoes] else {
            return nil
        }
        return OutfitDraft(
            top: top,
            bottom: bottom,
            shoes: shoes,
            outerwear: picked[.outerwear],
            accessory: picked[.accessory],
            socks: picked[.socks]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(slots, id: \.category) { slot in
                    slotPicker(category: slot.category, required: slot.required)
                }
                actionButtons
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private func slotPicker(category: Category, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(category.displayName).font(.subheadline.weight(.medium))
                if required {
                    Text("必选").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                if picked[category] != nil {
                    Button("清除") { picked[category] = nil }
                        .font(.caption)
                }
            }

            let items = candidates(for: category)
            if items.isEmpty {
                Text("衣橱里暂无可用的\(category.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            ItemThumbnail(item: item, size: 76)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(picked[category]?.id == item.id ? Color.accentColor : .clear, lineWidth: 3)
                                )
                                .onTapGesture { toggle(item, in: category) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                if let draft { favorite(draft) }
            } label: {
                Label("加入收藏", systemImage: "heart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                if let draft { wear(draft) }
            } label: {
                Label("今天穿这套", systemImage: "figure.stand")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(!isComplete)
        .padding(.top, 4)
    }

    private func toggle(_ item: ClothingItem, in category: Category) {
        if picked[category]?.id == item.id {
            picked[category] = nil
        } else {
            picked[category] = item
        }
    }

    private func favorite(_ draft: OutfitDraft) {
        WearService.addToFavorites(draft, scenario: nil, warmth: nil, in: modelContext)
        showToast("已加入收藏")
    }

    private func wear(_ draft: OutfitDraft) {
        WearService.wearToday(draft, in: modelContext)
        showToast("已设为今天穿这套")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}
