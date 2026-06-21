import SwiftUI

/// 衣橱网格的视图大小（大 / 中 / 小）。
///
/// 通过自适应 `GridItem` 的最小宽度控制一行卡片数量；小图模式隐藏文字、只保留图片与颜色点。
enum GalleryItemSize: String, CaseIterable, Identifiable {
    case large    // 大：约 1~2 列
    case medium   // 中：约 3 列
    case small    // 小：约 4~5 列

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .large:  return "大"
        case .medium: return "中"
        case .small:  return "小"
        }
    }

    var symbolName: String {
        switch self {
        case .large:  return "square"
        case .medium: return "square.grid.2x2"
        case .small:  return "square.grid.3x3"
        }
    }

    /// 单元格间距。
    var spacing: CGFloat {
        self == .small ? 8 : 16
    }

    /// 自适应网格列：按最小宽度自动决定列数。
    var columns: [GridItem] {
        let minWidth: CGFloat
        switch self {
        case .large:  minWidth = 168
        case .medium: minWidth = 108
        case .small:  minWidth = 74
        }
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    /// 是否展示文字标签（小图模式只保留图片 + 颜色点）。
    var showsLabels: Bool { self != .small }
}
