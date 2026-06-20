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

/// 根视图。阶段二仅有「衣橱」单页；后续阶段会扩展为 TabView（穿搭 / 日历 / 看板等）。
struct ContentView: View {
    var body: some View {
        WardrobeGalleryView()
    }
}
