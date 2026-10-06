import Foundation

/// 服务端数据存储：一个 SQLite 数据库加一个按内容寻址的媒体目录。
///
/// 所有数据库访问都经过这个 actor 串行执行；写操作在事务中完成，失败时整体回滚。
public actor ClosetStore {
    private let db: SQLiteDatabase
    public nonisolated let media: MediaStore

    /// 打开（必要时创建）数据目录中的数据库，并执行待执行的迁移。
    public init(directory: DataDirectory) throws {
        try directory.prepare()
        let db = try SQLiteDatabase(path: directory.databaseURL.path)
        _ = try db.query("PRAGMA journal_mode = WAL;")
        try MigrationRunner.migrate(db, backupBeforeUpgrade: directory.preMigrationBackupsURL)
        self.db = db
        self.media = MediaStore(root: directory.mediaURL)
    }

    /// 内存数据库，供测试使用。
    public init(inMemoryWithMediaRoot mediaRoot: URL) throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner.migrate(db, backupBeforeUpgrade: nil)
        self.db = db
        self.media = MediaStore(root: mediaRoot)
    }

    public func schemaVersion() throws -> Int {
        try MigrationRunner.currentVersion(db)
    }

    /// 在一个只读会话中执行查询。
    public func read<T: Sendable>(_ body: @Sendable (StoreSession) throws -> T) throws -> T {
        try body(StoreSession(db: db))
    }

    /// 在一个事务中执行写操作；闭包抛错时整体回滚。
    @discardableResult
    public func transaction<T: Sendable>(_ body: @Sendable (StoreSession) throws -> T) throws -> T {
        try db.transaction { try body(StoreSession(db: db)) }
    }

    /// 清理不再被引用的图片：先删数据库中的媒体行，再删磁盘上没有对应行的文件。
    ///
    /// 上传后尚未保存到单品的图片在宽限期内保留，见 `uploadGracePeriod`。
    /// - Parameter now: 当前时间，用于计算宽限期。
    /// - Returns: 删除的文件数。
    @discardableResult
    public func collectUnreferencedMedia(now: Date = Date()) throws -> Int {
        let session = StoreSession(db: db)
        let cutoff = now.addingTimeInterval(-Self.uploadGracePeriod)
        let referenced = try db.transaction { () -> Set<String> in
            try session.deleteMediaRows(try session.unreferencedMediaHashes(uploadsSince: cutoff))
            try session.deleteUploadRecords(before: cutoff)
            return try session.referencedMediaHashes()
        }
        var removed = 0
        for hash in media.storedHashes().subtracting(referenced) {
            media.remove(sha256: hash)
            removed += 1
        }
        return removed
    }

    /// 未保存到单品的上传图片保留的时长。
    public static let uploadGracePeriod: TimeInterval = 24 * 60 * 60
}
