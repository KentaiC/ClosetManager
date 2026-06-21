import Foundation

/// 性别（用户画像）。仅作本地画像数据，为后续「衣橱补充智能建议」做准备。
enum Gender: String, CaseIterable, Identifiable {
    case male          // 男
    case female        // 女
    case other         // 其他
    case unspecified   // 未填写

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male:        return "男"
        case .female:      return "女"
        case .other:       return "其他"
        case .unspecified: return "未填写"
        }
    }
}
