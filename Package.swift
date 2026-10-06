// swift-tools-version:6.0
import PackageDescription

// Closet Manager 的 Swift Package 入口。
//
// ClosetCore 是 iOS App 与本地 Web 服务端共享的领域核心。它的源文件就放在 App 的
// 文件系统同步分组 `ClosetManager/Core` 中：Xcode 把这些文件编译进 App 模块，
// SwiftPM 把同一批文件编译成独立的 ClosetCore 模块，两边只有一份源码。
//
// 服务端各层位于 `Server/Sources`：
// ClosetStorage   SQLite 数据库与按内容寻址的图片存储
// ClosetServices  应用服务：备份导入、只读查询，后续承载各项业务用例
// ClosetHTTP      HTTP API 与安全中间件（Hummingbird）
// ClosetServer    命令行入口 closet-server
let package = Package(
    name: "ClosetManager",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ClosetCore", targets: ["ClosetCore"]),
        .executable(name: "closet-server", targets: ["ClosetServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.20.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
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
        .target(
            name: "ClosetServices",
            dependencies: ["ClosetCore", "ClosetStorage"],
            path: "Server/Sources/ClosetServices"
        ),
        .target(
            name: "ClosetHTTP",
            dependencies: [
                "ClosetCore", "ClosetStorage", "ClosetServices",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            path: "Server/Sources/ClosetHTTP"
        ),
        .executableTarget(
            name: "ClosetServer",
            dependencies: [
                "ClosetHTTP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Server/Sources/ClosetServer"
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
        .testTarget(
            name: "ClosetServicesTests",
            dependencies: ["ClosetServices"],
            path: "Tests/ClosetServicesTests"
        ),
        .testTarget(
            name: "ClosetHTTPTests",
            dependencies: [
                "ClosetHTTP",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/ClosetHTTPTests"
        ),
    ]
)
