import SwiftUI

/// 颜色树形图：色块面积 ∝ 该颜色衣服数量，色块颜色即对应颜色，块上文字做对比度处理。
///
/// 用递归二分切割布局（slice-and-dice）：按权重把列表对半分，沿较长边按比例切，递归到单块。
struct ColorTreemapView: View {
    struct Tile: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let fill: Color
        /// 对比文字色（由背景明暗预先决定，保证可读）。
        let text: Color
    }

    let tiles: [Tile]
    var height: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            let placed = Self.layout(
                tiles.sorted { $0.count > $1.count },
                in: CGRect(origin: .zero, size: geo.size)
            )
            ForEach(placed, id: \.tile.id) { item in
                RoundedRectangle(cornerRadius: 5)
                    .fill(item.tile.fill)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.background, lineWidth: 1))
                    .overlay {
                        if item.rect.width > 44, item.rect.height > 28 {
                            VStack(spacing: 1) {
                                Text(item.tile.label).font(.caption2.weight(.semibold))
                                Text("\(item.tile.count)").font(.caption2)
                            }
                            .foregroundStyle(item.tile.text)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(2)
                        }
                    }
                    .frame(width: max(item.rect.width - 2, 0), height: max(item.rect.height - 2, 0))
                    .position(x: item.rect.midX, y: item.rect.midY)
            }
        }
        .frame(height: height)
    }

    private struct Placed {
        let tile: Tile
        let rect: CGRect
    }

    /// 递归二分切割布局。
    private static func layout(_ tiles: [Tile], in rect: CGRect) -> [Placed] {
        guard let first = tiles.first else { return [] }
        if tiles.count == 1 { return [Placed(tile: first, rect: rect)] }

        let total = tiles.reduce(0.0) { $0 + Double(max($1.count, 1)) }
        var firstGroup: [Tile] = []
        var accumulated = 0.0
        for tile in tiles {
            if accumulated >= total / 2, !firstGroup.isEmpty { break }
            firstGroup.append(tile)
            accumulated += Double(max(tile.count, 1))
        }
        if firstGroup.count == tiles.count { firstGroup.removeLast() }
        let secondGroup = Array(tiles[firstGroup.count...])

        let firstWeight = firstGroup.reduce(0.0) { $0 + Double(max($1.count, 1)) }
        let ratio = total > 0 ? firstWeight / total : 0.5

        let r1: CGRect
        let r2: CGRect
        if rect.width >= rect.height {
            let w1 = rect.width * ratio
            r1 = CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
            r2 = CGRect(x: rect.minX + w1, y: rect.minY, width: rect.width - w1, height: rect.height)
        } else {
            let h1 = rect.height * ratio
            r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
            r2 = CGRect(x: rect.minX, y: rect.minY + h1, width: rect.width, height: rect.height - h1)
        }
        return layout(firstGroup, in: r1) + layout(secondGroup, in: r2)
    }
}
