import SwiftUI

/// 可选中的胶囊标签（单个）。
struct SelectableChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// 基于胶囊标签的多选组件（场景 / 保暖标签 / 季节通用）。
struct ChipMultiSelect<Option: Identifiable & Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    var systemImage: ((Option) -> String?)? = nil
    @Binding var selection: Set<Option>
    /// 用户手动切换时回调（例如用于标记「季节已被手动编辑」）。
    var onToggle: (() -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                SelectableChip(
                    title: title(option),
                    systemImage: systemImage?(option),
                    isSelected: selection.contains(option)
                ) {
                    if selection.contains(option) {
                        selection.remove(option)
                    } else {
                        selection.insert(option)
                    }
                    onToggle?()
                }
            }
        }
    }
}
