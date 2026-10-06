import Foundation

/// 应用服务的业务错误，由 HTTP 层映射为 4xx 响应。
public enum ServiceError: Error, Equatable, CustomStringConvertible {
    /// 请求的数据不存在。
    case notFound(String)
    /// 请求与当前状态冲突，例如对已经脱下的穿搭再次脱下。
    case conflict(String)
    /// 请求内容不合法。
    case invalid(String)

    public var description: String {
        switch self {
        case .notFound(let message), .conflict(let message), .invalid(let message): return message
        }
    }
}

/// 把枚举原始值解析为枚举，失败时给出中文错误。
func parseEnum<E: RawRepresentable>(_ raw: String, field: String) throws -> E where E.RawValue == String {
    guard let value = E(rawValue: raw) else { throw ServiceError.invalid("字段 \(field) 的值「\(raw)」无效。") }
    return value
}

func parseOptionalEnum<E: RawRepresentable>(_ raw: String?, field: String) throws -> E? where E.RawValue == String {
    guard let raw, !raw.isEmpty else { return nil }
    return try parseEnum(raw, field: field) as E
}
