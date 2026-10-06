import Foundation
import ClosetCore

/// 导入预检或导入结果中的一条问题。
public struct ImportIssue: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        // 错误：阻止导入。
        case unsupportedVersion
        case invalidValue
        case subtypeCategoryMismatch
        case warmthScoreOutOfRange
        case invalidImageData
        case duplicateID
        // 警告：导入照常进行，问题被记录。
        case missingItemReference
        case missingOutfitReference
        case duplicateMember
        case multipleActiveRecords
        case activeRecordConflict
        case inconsistentLaundryState
        case unknownImageFormat
        case inconsistentWarmthLevels
    }

    public var code: Code
    public var message: String
    public var entity: String?
    public var id: String?

    public init(_ code: Code, _ message: String, entity: String? = nil, id: String? = nil) {
        self.code = code
        self.message = message
        self.entity = entity
        self.id = id
    }
}

/// 某类记录的导入数量。
public struct ImportCounts: Codable, Sendable, Equatable {
    /// 备份文件中的数量。
    public var inBackup = 0
    /// 将要写入（或已写入）的数量。
    public var toImport = 0
    /// 合并模式下因 id 已存在而跳过的数量。
    public var skippedExisting = 0

    public init(inBackup: Int = 0, toImport: Int = 0, skippedExisting: Int = 0) {
        self.inBackup = inBackup
        self.toImport = toImport
        self.skippedExisting = skippedExisting
    }
}

/// 导入预检报告。`applied` 为 true 表示数据已写入。
public struct ImportReport: Codable, Sendable {
    public var mode: RestoreMode
    public var dryRun: Bool
    public var backupVersion: Int
    public var items = ImportCounts()
    public var outfits = ImportCounts()
    public var wearRecords = ImportCounts()
    public var imageCount = 0
    public var imageBytes = 0
    public var warnings: [ImportIssue] = []
    public var errors: [ImportIssue] = []
    public var applied = false
    /// 写入前自动保存的当前数据备份的文件名，位于数据目录的 `backups/before-import`。
    public var preImportBackup: String?

    public init(mode: RestoreMode, dryRun: Bool, backupVersion: Int) {
        self.mode = mode
        self.dryRun = dryRun
        self.backupVersion = backupVersion
    }

    public var canApply: Bool { errors.isEmpty }
}

/// 导入失败。
public enum ImportError: Error, CustomStringConvertible {
    /// 文件不是有效的 `.wardrobe` JSON。
    case unreadable(String)
    /// 预检发现错误，未写入任何数据。
    case rejected(ImportReport)

    public var description: String {
        switch self {
        case .unreadable(let detail): return "无法读取备份文件：\(detail)"
        case .rejected(let report): return "备份文件存在 \(report.errors.count) 个错误，未导入任何数据。"
        }
    }
}
