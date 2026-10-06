import Foundation

/// 本地数据目录的布局。
///
/// ```text
/// <root>/closet.sqlite
/// <root>/media/
/// <root>/backups/pre-migration/
/// <root>/tmp/
/// ```
public struct DataDirectory: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var databaseURL: URL { root.appendingPathComponent("closet.sqlite") }
    public var mediaURL: URL { root.appendingPathComponent("media", isDirectory: true) }
    public var preMigrationBackupsURL: URL { root.appendingPathComponent("backups/pre-migration", isDirectory: true) }
    public var temporaryURL: URL { root.appendingPathComponent("tmp", isDirectory: true) }

    /// 创建目录结构，权限仅限当前用户。
    public func prepare() throws {
        for directory in [root, mediaURL, temporaryURL] {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    /// 默认位置：macOS 为 `~/Library/Application Support/ClosetManager`，
    /// Linux 为 `$XDG_DATA_HOME/ClosetManager` 或 `~/.local/share/ClosetManager`。
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
        return base.appendingPathComponent("ClosetManager", isDirectory: true)
    }
}
