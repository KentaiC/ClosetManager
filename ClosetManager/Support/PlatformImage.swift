import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    /// 从存储的图片二进制数据创建 SwiftUI `Image`（跨 iOS / macOS）。
    ///
    /// 数据无法解码时返回 nil，调用方应自行提供占位视图。
    init?(platformData data: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        return nil
        #endif
    }
}
