import SwiftUI

/// 衣橱网格中的单品卡片。
///
/// 零遮挡原则：主色展示**独占卡片底部一块独立区域**，绝不与衣物图片、名称或标签重叠。
/// - `compact == false`：图片 → 名称/场景 → 主色行（色块 + 中文色名）。
/// - `compact == true`（小图模式）：图片 → 底部细长主色条；隐藏全部文字。
struct ItemCard: View {
    let item: ClothingItem
    var compact: Bool = false

    /// 用户自定义卡片圆角（@AppStorage）。
    @AppStorage(UIPreferenceKeys.cornerRadius) private var storedRadius = UIPreferenceKeys.defaultCornerRadius

    /// 实际圆角：小图模式略收紧。
    private var radius: CGFloat { compact ? max(CGFloat(storedRadius) - 4, 4) : CGFloat(storedRadius) }

    private var displayImageData: Data? {
        item.processedImageData ?? item.originalImageData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            imageArea
            if compact {
                colorBar
            } else {
                infoArea
            }
        }
        .padding(compact ? 5 : 8)
        .background(.background, in: RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - 图片区（仅图片 + 洗衣角标，主色不在此叠加，确保不遮挡主体图）

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
                            .padding(compact ? 3 : 6)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if item.status == .inLaundry {
                laundryBadge.padding(compact ? 4 : 6)
            }
        }
    }

    private var laundryBadge: some View {
        Group {
            if compact {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                    .padding(4)
                    .background(.thinMaterial, in: Circle())
                    .foregroundStyle(.blue)
            } else {
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
        }
    }

    // MARK: - 小图模式：底部独立主色条

    private var colorBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(item.dominantColor.color)
            .frame(height: 6)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary, lineWidth: 0.5))
            .padding(.horizontal, 2)
    }

    // MARK: - 普通模式：文字 + 独立主色行

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

            colorRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    /// 主色行：色块 + 中文色名（独立一行，绝不与上方文字/图片重叠）。
    private var colorRow: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(item.dominantColor.color)
                .frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary, lineWidth: 0.5))
            Text(item.dominantColor.refinedColorName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
