import Foundation

/// 适用场景（一件单品可同时适配多个场景，多选）。
enum Scenario: String, Codable, CaseIterable, Identifiable {
    case work     // 通勤
    case casual   // 休闲
    case sport    // 运动
    case formal   // 正式

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .work:   return "通勤"
        case .casual: return "休闲"
        case .sport:  return "运动"
        case .formal: return "正式"
        }
    }

    /// 与之冲突、不应同时勾选的场景。
    ///
    /// 业务约束：正式（如西装）绝不能与「运动」绑定，反之亦然。
    /// 录入 / 编辑层据此做校验提示。
    var conflictingScenarios: Set<Scenario> {
        switch self {
        case .formal: return [.sport]
        case .sport:  return [.formal]
        case .work, .casual: return []
        }
    }
}
