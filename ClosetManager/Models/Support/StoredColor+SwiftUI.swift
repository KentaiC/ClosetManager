import SwiftUI

extension StoredColor {
    /// 还原为 SwiftUI Color（仅供 UI 展示使用）。
    ///
    /// 与 `StoredColor` 本体分开存放：本体位于共享的 `Core/`，只依赖 Foundation；
    /// SwiftUI 桥接只属于 App。
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
