import SwiftUI
import SwiftData

/// 日历历史：按日期倒序展示已穿过的穿搭记录（`WearRecord`）。
///
/// 「脱下」流转完成后，当天的穿搭会自动出现在这里。完整的月历视图留待后续阶段。
struct CalendarHistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WearRecord.date, order: .reverse)
    private var records: [WearRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "还没有穿搭记录",
                        systemImage: "calendar",
                        description: Text("在「穿搭」里选择「今天穿这套」，记录就会出现在这里。")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            recordRow(record)
                        }
                        .onDelete(perform: deleteRecords)
                    }
                }
            }
            .navigationTitle("日历")
        }
    }

    private func recordRow(_ record: WearRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if record.isActive {
                    Text("正在穿")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(record.items) { item in
                        ItemThumbnail(item: item, size: 52)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(records[index])
        }
    }
}
