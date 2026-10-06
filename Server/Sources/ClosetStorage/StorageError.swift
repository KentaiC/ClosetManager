import Foundation

/// 存储层错误。
public enum StorageError: Error, Equatable, CustomStringConvertible {
    /// 数据库由更新版本的程序创建，当前程序无法安全读取。
    case schemaTooNew(found: Int, supported: Int)
    /// 数据库中的某行无法转换为领域类型。
    case corruptRow(table: String, id: String, detail: String)
    /// 媒体文件缺失。
    case missingMedia(sha256: String)

    public var description: String {
        switch self {
        case .schemaTooNew(let found, let supported):
            return "数据库版本为 \(found)，当前程序最高支持 \(supported)，请升级程序。"
        case .corruptRow(let table, let id, let detail):
            return "数据表 \(table) 中的记录 \(id) 无法读取：\(detail)"
        case .missingMedia(let sha256):
            return "图片文件缺失：\(sha256)"
        }
    }
}
