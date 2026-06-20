import Foundation
import SwiftData

/// 应用数据层 Schema 与 ModelContainer 的集中配置。
///
/// 在 App 入口用 `.modelContainer(ClosetSchema.makeContainer())` 注入；
/// SwiftUI 预览 / 单元测试可用 `makeContainer(inMemory: true)` 获取内存容器。
enum ClosetSchema {
    /// 全部需注册的 @Model 类型。新增模型时只需在此登记。
    static var models: [any PersistentModel.Type] {
        [ClothingItem.self, Outfit.self, WearRecord.self]
    }

    static var schema: Schema { Schema(models) }

    /// 创建数据容器。
    /// - Parameter inMemory: 为 true 时仅存内存（预览 / 测试用），不落盘。
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("无法创建 ModelContainer：\(error)")
        }
    }
}
