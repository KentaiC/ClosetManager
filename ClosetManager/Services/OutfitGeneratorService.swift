import Foundation

/// App 端的穿搭草稿类型：共享核心中的 `OutfitDraftOf`，单品固定为 `ClothingItem`。
typealias OutfitDraft = OutfitDraftOf<ClothingItem>

/// App 端穿搭生成入口。
///
/// 算法本体位于共享核心 `OutfitGenerationEngine`，App 与本地 Web 服务端共用同一份实现；
/// 这里保留原有的调用方式，视图层无需改动。
enum OutfitGeneratorService {
    typealias Result = OutfitGenerationResult<ClothingItem>

    /// 根据「当前天气档位 + 场景」生成多套叠穿穿搭。
    /// - Parameter requireWaterproof: 雨雪天气强关联——为 true 时强制外套与鞋子必须防水，且外套必选。
    static func generate(
        from items: [ClothingItem],
        warmth: WarmthLevel,
        scenario: Scenario,
        requireWaterproof: Bool = false,
        maxCount: Int = 8
    ) -> Result {
        OutfitGenerationEngine.generate(
            from: items,
            warmth: warmth,
            scenario: scenario,
            requireWaterproof: requireWaterproof,
            maxCount: maxCount
        )
    }
}

// MARK: - SwiftData 模型接入共享核心的只读协议

extension ClothingItem: WardrobeItemRepresentable {}
extension WearRecord: WearRecordRepresentable {}
