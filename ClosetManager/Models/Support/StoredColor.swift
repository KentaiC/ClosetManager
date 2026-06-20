import Foundation
import SwiftUI

/// 用于持久化存储颜色的轻量结构体。
///
/// - SwiftData 会将其作为「复合属性 (Composite Attribute)」整体存储到单品记录中。
/// - 采用 sRGB 颜色空间、0...1 范围的分量，跨 iOS / macOS 通用（避免直接依赖 UIColor / NSColor）。
/// - 由 CoreImage 取色后写入；UI 层通过 `color` 计算属性还原为 SwiftUI Color。
///
/// 标记 `nonisolated`：本类型是纯数据值，需被 SwiftData 的非隔离存取代码使用，
/// 不应被工程的「Default Actor Isolation = MainActor」隐式绑定到主线程。
nonisolated struct StoredColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension StoredColor {
    /// 还原为 SwiftUI Color（仅供 UI 展示使用）。
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// 十六进制字符串，便于调试与标签展示（如 "#1A2B3C"）。
    var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// HSB 分量（hue: 0...360, saturation: 0...1, brightness: 0...1）。
    /// 供 `ColorCategory.classify(_:)` 做颜色归类时使用。
    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(red, green, blue)
        let minV = min(red, green, blue)
        let delta = maxV - minV

        var hue: Double = 0
        if delta != 0 {
            if maxV == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }

        let saturation = maxV == 0 ? 0 : delta / maxV
        return (hue, saturation, maxV)
    }
}
