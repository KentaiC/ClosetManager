import SwiftUI

/// GitHub 贡献图风格的穿搭活跃度热力图。
///
/// 横向以「周」为列、纵向以「星期」为行，单元格颜色深浅表示当天穿搭打卡次数。
struct ActivityHeatmapView: View {
    /// 每日打卡次数（key 为 startOfDay）。
    let activity: [Date: Int]
    /// 展示最近多少周。
    var weeks: Int = 16

    private let calendar = Calendar.current
    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 3

    /// 从对齐到周首的起点，到今天的全部日期（列优先：每 7 个为一周列）。
    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        let totalDays = weeks * 7
        let rawStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) ?? today
        let start = calendar.dateInterval(of: .weekOfYear, for: rawStart)?.start ?? rawStart
        var result: [Date] = []
        var cursor = start
        while cursor <= today {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today.addingTimeInterval(86_400)
        }
        return result
    }

    /// LazyHGrid 以 7 行（星期）排布，列优先填充即形成「每列一周」。
    private var rows: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: spacing) {
                    ForEach(days, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: activity[day] ?? 0))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                .padding(.vertical, 2)
            }
            legend
        }
    }

    /// 强度配色：0 次最浅，次数越多越深。
    private func color(for count: Int) -> Color {
        switch count {
        case 0:  return Color.gray.opacity(0.15)
        case 1:  return Color.accentColor.opacity(0.35)
        case 2:  return Color.accentColor.opacity(0.6)
        default: return Color.accentColor
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach([0, 1, 2, 3], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
