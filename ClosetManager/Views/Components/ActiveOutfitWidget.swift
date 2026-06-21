import SwiftUI
import SwiftData

/// 「目前正在穿」常驻看板。
///
/// - 有活动穿搭时：展示该套所有单品缩略图，并提供醒目的「脱下并扔进洗衣袋」按钮。
/// - 无活动穿搭时：显示「今天尚未选择穿搭」提示。
///
/// 通过 `@Query` 监听 `isActive == true` 的 `WearRecord`，状态变更后 UI 自动刷新。
struct ActiveOutfitWidget: View {
    @Query(filter: #Predicate<WearRecord> { $0.isActive },
           sort: \WearRecord.date, order: .reverse)
    private var activeRecords: [WearRecord]

    @State private var showTakeOff = false

    private var activeRecord: WearRecord? { activeRecords.first }

    var body: some View {
        Group {
            if let activeRecord {
                activeCard(activeRecord)
            } else {
                emptyCard
            }
        }
        .sheet(isPresented: $showTakeOff) {
            if let activeRecord {
                TakeOffSheet(record: activeRecord)
            }
        }
    }

    private func activeCard(_ record: WearRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("目前正在穿", systemImage: "figure.stand")
                    .font(.headline)
                Spacer()
                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(record.items) { item in
                        ItemThumbnail(item: item, size: 64)
                    }
                }
            }

            Button(role: .destructive) {
                showTakeOff = true
            } label: {
                Label("脱下并扔进洗衣袋", systemImage: "washer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }

    private var emptyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "tshirt")
                .foregroundStyle(.tertiary)
            Text("今天尚未选择穿搭")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}
