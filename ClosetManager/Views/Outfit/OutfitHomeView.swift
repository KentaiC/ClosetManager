import SwiftUI

/// 「穿搭」Tab 容器：智能生成 / 收藏夹 / 自由拼搭 三个子页，用分段控件切换。
struct OutfitHomeView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case generate = "智能生成"
        case favorites = "收藏夹"
        case manual = "自由拼搭"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .generate

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .generate:
                    OutfitGeneratorView()
                case .favorites:
                    FavoritesView()
                case .manual:
                    ManualOutfitBuilderView()
                }
            }
            .navigationTitle("穿搭")
        }
    }
}
