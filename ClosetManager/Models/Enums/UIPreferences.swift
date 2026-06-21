import SwiftUI

/// 全局强调色选项（@AppStorage 持久化，应用于根视图 `.tint`）。
enum AccentChoice: String, CaseIterable, Identifiable {
    case purple, blue, teal, green, orange, pink, red

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purple: return "紫色"
        case .blue:   return "蓝色"
        case .teal:   return "青色"
        case .green:  return "绿色"
        case .orange: return "橙色"
        case .pink:   return "粉色"
        case .red:    return "红色"
        }
    }

    var color: Color {
        switch self {
        case .purple: return .purple
        case .blue:   return .blue
        case .teal:   return .teal
        case .green:  return .green
        case .orange: return .orange
        case .pink:   return .pink
        case .red:    return .red
        }
    }
}

/// 外观模式锁定（跟随系统 / 锁定浅色 / 锁定深色）。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// UI 自定义相关的 @AppStorage key 与默认值集中管理。
enum UIPreferenceKeys {
    static let accent = "ui.accent"
    static let appearance = "ui.appearance"
    static let cornerRadius = "ui.cornerRadius"

    static let defaultCornerRadius: Double = 16
}
