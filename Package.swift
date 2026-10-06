// swift-tools-version:6.0
import PackageDescription

// Closet Manager 的 Swift Package 入口。
//
// ClosetCore 是 iOS App 与本地 Web 服务端共享的领域核心。它的源文件就放在 App 的
// 文件系统同步分组 `ClosetManager/Core` 中：Xcode 把这些文件编译进 App 模块，
// SwiftPM 把同一批文件编译成独立的 ClosetCore 模块，两边只有一份源码。
//
// 服务端各层位于 `Server/Sources`：
// ClosetStorage  SQLite 数据库与按内容寻址的图片存储
let package = Package(
    name: "ClosetManager",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ClosetCore", targets: ["ClosetCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "ClosetCore",
            path: "ClosetManager/Core",
            // 与 App 的 SWIFT_VERSION = 5.0 保持一致，保证两边按同一语言模式编译。
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Linux 上通过系统库使用 SQLite；macOS 直接使用 SDK 中的 SQLite3 模块。
        .systemLibrary(
            name: "CSQLite",
            path: "Server/Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "ClosetStorage",
            dependencies: [
                "ClosetCore",
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Server/Sources/ClosetStorage"
        ),
        .testTarget(
            name: "ClosetCoreTests",
            dependencies: ["ClosetCore"],
            path: "Tests/ClosetCoreTests"
        ),
        .testTarget(
            name: "ClosetStorageTests",
            dependencies: ["ClosetStorage"],
            path: "Tests/ClosetStorageTests"
        ),
    ]
)
