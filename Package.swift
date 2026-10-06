// swift-tools-version:6.0
import PackageDescription

// Closet Manager 的 Swift Package 入口。
//
// ClosetCore 是 iOS App 与本地 Web 服务端共享的领域核心。它的源文件就放在 App 的
// 文件系统同步分组 `ClosetManager/Core` 中：Xcode 把这些文件编译进 App 模块，
// SwiftPM 把同一批文件编译成独立的 ClosetCore 模块，两边只有一份源码。
let package = Package(
    name: "ClosetManager",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ClosetCore", targets: ["ClosetCore"]),
    ],
    targets: [
        .target(
            name: "ClosetCore",
            path: "ClosetManager/Core",
            // 与 App 的 SWIFT_VERSION = 5.0 保持一致，保证两边按同一语言模式编译。
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClosetCoreTests",
            dependencies: ["ClosetCore"],
            path: "Tests/ClosetCoreTests"
        ),
    ]
)
