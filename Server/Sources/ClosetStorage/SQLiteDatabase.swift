import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// SQLite 中的一个值。
public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

/// SQLite 调用失败。
public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public let sql: String?

    /// 是否为约束违反（主键、唯一、外键、CHECK、NOT NULL）。
    public var isConstraintViolation: Bool { code & 0xFF == SQLITE_CONSTRAINT }

    public var description: String {
        "SQLite error \(code): \(message)" + (sql.map { " [\($0)]" } ?? "")
    }
}

/// 查询结果中的一行。
public struct SQLiteRow: Sendable {
    let columns: [String: Int]
    let values: [SQLiteValue]

    public subscript(_ column: String) -> SQLiteValue {
        guard let index = columns[column] else { return .null }
        return values[index]
    }

    public func string(_ column: String) -> String? {
        if case .text(let value) = self[column] { return value }
        return nil
    }

    public func int(_ column: String) -> Int? {
        switch self[column] {
        case .integer(let value): return Int(value)
        case .real(let value): return Int(value)
        default: return nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch self[column] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    public func bool(_ column: String) -> Bool? { int(column).map { $0 != 0 } }

    public func data(_ column: String) -> Data? {
        if case .blob(let value) = self[column] { return value }
        return nil
    }
}

/// 一个 SQLite 连接的薄封装。
///
/// 不做线程同步：由持有它的 actor 串行访问。
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    public let path: String

    /// - Parameter path: 数据库文件路径；传 `":memory:"` 得到内存数据库。
    public init(path: String) throws {
        self.path = path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close_v2(db)
            throw SQLiteError(code: rc, message: message, sql: nil)
        }
        handle = db
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// 执行一段（可含多条语句的）SQL，不读取结果。
    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteError(code: rc, message: message, sql: sql)
        }
    }

    /// 执行单条语句，返回受影响的行数。
    @discardableResult
    public func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(rc, sql) }
        return Int(sqlite3_changes(handle))
    }

    /// 执行查询并读取全部结果行。
    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let count = Int(sqlite3_column_count(statement))
        var columns: [String: Int] = [:]
        for index in 0..<count {
            columns[String(cString: sqlite3_column_name(statement, Int32(index)))] = index
        }
        var rows: [SQLiteRow] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error(rc, sql) }
            var values: [SQLiteValue] = []
            values.reserveCapacity(count)
            for index in 0..<Int32(count) {
                values.append(readColumn(statement, index))
            }
            rows.append(SQLiteRow(columns: columns, values: values))
        }
        return rows
    }

    /// 在一个事务中执行 `body`；`body` 抛错时回滚。
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - 内部

    private var lastErrorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private func error(_ rc: Int32, _ sql: String) -> SQLiteError {
        SQLiteError(code: sqlite3_extended_errcode(handle), message: lastErrorMessage, sql: sql)
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else { throw error(rc, sql) }
        let expected = Int(sqlite3_bind_parameter_count(statement))
        guard expected == bindings.count else {
            sqlite3_finalize(statement)
            throw SQLiteError(code: SQLITE_RANGE, message: "需要 \(expected) 个参数，实际 \(bindings.count) 个", sql: sql)
        }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let bindRC: Int32
            switch value {
            case .null:
                bindRC = sqlite3_bind_null(statement, index)
            case .integer(let number):
                bindRC = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                bindRC = sqlite3_bind_double(statement, index, number)
            case .text(let text):
                bindRC = sqlite3_bind_text(statement, index, text, -1, SQLiteDatabase.transient)
            case .blob(let data):
                if data.isEmpty {
                    bindRC = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    bindRC = data.withUnsafeBytes {
                        sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), SQLiteDatabase.transient)
                    }
                }
            }
            guard bindRC == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw error(bindRC, sql)
            }
        }
        return statement
    }

    private func readColumn(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .text("") }
            let length = Int(sqlite3_column_bytes(statement, index))
            return .text(String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self))
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let pointer = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: length))
        default:
            return .null
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
