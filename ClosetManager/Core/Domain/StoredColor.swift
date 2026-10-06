import Foundation

/// 用于持久化存储颜色的轻量结构体。
///
/// - SwiftData 会将其作为「复合属性 (Composite Attribute)」整体存储到单品记录中。
/// - 采用 sRGB 颜色空间、0...1 范围的分量，跨 iOS / macOS 通用（避免直接依赖 UIColor / NSColor）。
/// - 由 CoreImage 取色后写入；App 的 UI 层通过 `StoredColor+SwiftUI.swift` 中的 `color` 还原为 SwiftUI Color。
/// - 本文件只依赖 Foundation，供 App 与本地 Web 服务端共享。
public struct StoredColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension StoredColor {
    /// 十六进制字符串，便于调试与标签展示（如 "#1A2B3C"）。
    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// HSB 分量（hue: 0...360, saturation: 0...1, brightness: 0...1）。
    /// 供 `ColorCategory.classify(_:)` 做颜色归类时使用。
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
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
