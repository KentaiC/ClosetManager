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

/// 根视图：底部 TabView 导航。
///
/// 「衣橱」「洗衣袋」已可用；「穿搭」「日历」「看板」为后续阶段，先用占位页占位。
struct ContentView: View {
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

            ComingSoonView(
                title: "看板",
                systemImage: "chart.pie",
                message: "衣橱数据分析看板即将推出。"
            )
            .tabItem { Label("看板", systemImage: "chart.pie") }
        }
    }
}
