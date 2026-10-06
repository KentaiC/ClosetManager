import Foundation

/// 单品的只读字段视图，供共享核心中的规则使用。
///
/// App 的 `ClothingItem`（SwiftData）与本地 Web 服务端的单品记录都遵循本协议，
/// 因此穿搭生成、统计等规则只需实现一次。
public protocol WardrobeItemRepresentable {
    var id: UUID { get }
    var category: Category { get }
    var subtype: Subtype? { get }
    var scenarios: [Scenario] { get }
    var status: ItemStatus { get }
    var isWaterproof: Bool { get }
    var warmthScore: Int { get }
    var dominantColorCategory: ColorCategory { get }
}

/// 穿着记录的只读字段视图，供共享核心中的统计规则使用。
public protocol WearRecordRepresentable {
    associatedtype Item: WardrobeItemRepresentable
    var date: Date { get }
    var items: [Item] { get }
}
