import SwiftUI

/// 一套穿搭草稿的展示卡片（生成结果 / 自由拼搭预览复用）。
///
/// 展示各槽位单品，并提供「加入收藏」「今天穿这套」两个操作（由外部注入回调）。
struct OutfitDraftCard: View {
    let draft: OutfitDraft
    var onFavorite: (() -> Void)?
    var onWear: (() -> Void)?

    /// 按槽位整理（含标签），仅展示存在的单品。
    private var slots: [(label: String, item: ClothingItem)] {
        var result: [(String, ClothingItem)] = []
        if let outerwear = draft.outerwear { result.append(("外套", outerwear)) }
        result.append(("上装", draft.top))
        result.append(("下装", draft.bottom))
        if let socks = draft.socks { result.append(("袜子", socks)) }
        result.append(("鞋子", draft.shoes))
        if let accessory = draft.accessory { result.append(("配饰", accessory)) }
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                ForEach(slots, id: \.item.id) { slot in
                    VStack(spacing: 6) {
                        ItemThumbnail(item: slot.item, size: 84)
                        Text(slot.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if onFavorite != nil || onWear != nil {
                HStack(spacing: 12) {
                    if let onFavorite {
                        Button {
                            onFavorite()
                        } label: {
                            Label("加入收藏", systemImage: "heart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let onWear {
                        Button {
                            onWear()
                        } label: {
                            Label("今天穿这套", systemImage: "figure.stand")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
    }
}
