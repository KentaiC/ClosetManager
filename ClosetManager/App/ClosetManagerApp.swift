import SwiftUI
import SwiftData

/// App 入口：注入 SwiftData 容器，承载根视图。
///
/// 若你在 Xcode 新建项目时已自动生成同名 `@main` 入口，请用本文件内容替换它，
/// 或仅把 `.modelContainer(ClosetSchema.makeContainer())` 这一行合并进去即可。
@main
struct ClosetManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ClosetSchema.makeContainer())
    }
}

/// 根视图：底部 TabView 导航。应用全局强调色与外观模式（用户自定义，@AppStorage）。
struct ContentView: View {
    @AppStorage(UIPreferenceKeys.accent) private var accentRaw = AccentChoice.purple.rawValue
    @AppStorage(UIPreferenceKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .purple).color }
    private var appearance: ColorScheme? { (AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme }

    var body: some View {
        TabView {
            WardrobeGalleryView()
                .tabItem { Label("衣橱", systemImage: "square.grid.2x2") }

            LaundryView()
                .tabItem { Label("洗衣房", systemImage: "washer") }

            OutfitHomeView()
                .tabItem { Label("穿搭", systemImage: "sparkles") }

            CalendarHistoryView()
                .tabItem { Label("日历", systemImage: "calendar") }

            AnalyticsDashboardView()
                .tabItem { Label("看板", systemImage: "chart.pie") }
        }
        .tint(accent)
        .preferredColorScheme(appearance)
    }
}
