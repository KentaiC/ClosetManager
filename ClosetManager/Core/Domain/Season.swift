import Foundation

/// 适用季节（可多选）。
///
/// 默认由单品的保暖标签 `WarmthLevel` 自动推导（见 `derive(from:)`），
/// 同时允许用户在录入 / 编辑界面手动调整覆盖。
public enum Season: String, Codable, CaseIterable, Identifiable, Sendable {
    case spring   // 春
    case summer   // 夏
    case autumn   // 秋
    case winter   // 冬

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }

    public var symbolName: String {
        switch self {
        case .spring: return "leaf"
        case .summer: return "sun.max"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }
}

extension Season {
    /// 依据一组保暖标签推导适用季节（并按 `spring→summer→autumn→winter` 稳定排序）。
    public static func derive(from warmthLevels: [WarmthLevel]) -> [Season] {
        let union = warmthLevels.reduce(into: Set<Season>()) { result, level in
            result.formUnion(level.seasons)
        }
        return Season.allCases.filter { union.contains($0) }
    }
}
