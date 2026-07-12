import Foundation
import SwiftUI
import PhotosUI

/// 批量录入的统一图片来源，让「相册多选 / 从文件多选 / 拖拽释放」三种入口
/// 都能汇入同一套批量序列化编辑器，后续打标签流程完全一致。
struct ImageSource: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case photo(PhotosPickerItem)  // 相册项（延迟加载）
        case data(Data)               // 已加载的图片数据（来自文件 / 拖拽）
    }

    static func photo(_ item: PhotosPickerItem) -> ImageSource { ImageSource(kind: .photo(item)) }
    static func data(_ data: Data) -> ImageSource { ImageSource(kind: .data(data)) }
}
