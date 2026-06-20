import SwiftUI

/// 衣橱网格中的单品卡片。
///
/// 展示去背后的主体图（优先 `processedImageData`，回退原图），
/// 并在角落用极简标签显示「洗衣袋状态」与「适用场景」。
struct ItemCard: View {
    let item: ClothingItem

    /// 优先展示抠图结果，缺失时回退到原图。
    private var displayImageData: Data? {
        item.processedImageData ?? item.originalImageData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            imageArea
            infoArea
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - 图片区

    private var imageArea: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let data = displayImageData, let image = Image(platformData: data) {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if item.status == .inLaundry {
                laundryBadge
                    .padding(6)
            }
        }
    }

    /// 「在洗衣袋」状态角标。
    private var laundryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill")
            Text("洗衣袋")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.blue)
    }

    // MARK: - 信息区

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name.isEmpty ? item.category.displayName : item.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if !item.scenarios.isEmpty {
                Text(item.scenarios.map(\.displayName).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}
