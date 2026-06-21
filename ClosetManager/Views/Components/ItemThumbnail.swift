import SwiftUI

/// 单品小缩略图（穿搭卡片 / 正在穿看板 / 脱下弹窗 / 日历等复用）。
struct ItemThumbnail: View {
    let item: ClothingItem
    var size: CGFloat = 64

    private var imageData: Data? {
        item.processedImageData ?? item.originalImageData
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary.opacity(0.4))
            .frame(width: size, height: size)
            .overlay {
                if let imageData, let image = Image(platformData: imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
