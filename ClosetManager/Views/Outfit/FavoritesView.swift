import SwiftUI
import SwiftData

/// 收藏夹：展示所有被标记为收藏的 `Outfit`，可「今天穿这套」或删除。
struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Outfit> { $0.isFavorite },
           sort: \Outfit.createdAt, order: .reverse)
    private var favorites: [Outfit]

    @State private var toast: String?

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "还没有收藏的穿搭",
                    systemImage: "heart",
                    description: Text("在「智能生成」或「自由拼搭」里把喜欢的组合加入收藏。")
                )
            } else {
                List {
                    ForEach(favorites) { outfit in
                        favoriteRow(outfit)
                    }
                    .onDelete(perform: deleteFavorites)
                }
            }
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

    private func favoriteRow(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(outfit.items) { item in
                        ItemThumbnail(item: item, size: 56)
                    }
                }
            }
            HStack {
                if let scenario = outfit.targetScenario {
                    Text(scenario.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    wear(outfit)
                } label: {
                    Label("今天穿这套", systemImage: "figure.stand")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func wear(_ outfit: Outfit) {
        WearService.wearOutfit(outfit, in: modelContext)
        showToast("已设为今天穿这套")
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}
