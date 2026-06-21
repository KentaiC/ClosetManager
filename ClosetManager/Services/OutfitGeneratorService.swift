import Foundation

/// 一套穿搭草稿（尚未持久化）。由生成引擎或手动拼搭产出，用户确认后再转为持久化 `Outfit` 或 `WearRecord`。
///
/// 结构约束：[上装(必选)] + [下装(必选)] + [鞋子(必选)] + [外套(可选)] + [配饰(可选)] + [袜子(可选)]。
struct OutfitDraft: Identifiable {
    let id = UUID()
    var top: ClothingItem
    var bottom: ClothingItem
    var shoes: ClothingItem
    var outerwear: ClothingItem?
    var accessory: ClothingItem?
    var socks: ClothingItem?

    /// 全部单品（按穿戴层次排序，便于展示）。
    var allItems: [ClothingItem] {
        [outerwear, top, bottom, socks, shoes, accessory].compactMap { $0 }
    }
}

/// 本地穿搭生成引擎（纯函数，与 UI 解耦）。
enum OutfitGeneratorService {
    /// 生成结果：要么有若干草稿，要么给出缺失的必选分类用于提示。
    struct Result {
        var drafts: [OutfitDraft]
        var missingRequired: [Category]
    }

    /// 根据保暖标签与场景，从可用单品中组装多套穿搭。
    /// - Parameters:
    ///   - items: 全部单品（内部仅取 `inWardrobe` 且匹配条件者）。
    ///   - warmth: 目标保暖标签 / 当前天气。
    ///   - scenario: 目标场景。
    ///   - maxCount: 最多生成套数。
    static func generate(
        from items: [ClothingItem],
        warmth: WarmthLevel,
        scenario: Scenario,
        maxCount: Int = 8
    ) -> Result {
        // 1. 仅在衣橱中、且同时匹配温度与场景的单品参与。
        let pool = items.filter {
            $0.isAvailable
            && $0.isSuitable(forWarmth: warmth)
            && $0.isSuitable(forScenario: scenario)
        }

        let tops = pool.filter { $0.category == .top }.shuffled()
        let bottoms = pool.filter { $0.category == .bottom }.shuffled()
        let shoes = pool.filter { $0.category == .shoes }.shuffled()
        let outers = pool.filter { $0.category == .outerwear }.shuffled()
        let accessories = pool.filter { $0.category == .accessory }.shuffled()
        let socks = pool.filter { $0.category == .socks }.shuffled()

        // 2. 校验必选分类是否齐备。
        var missing: [Category] = []
        if tops.isEmpty { missing.append(.top) }
        if bottoms.isEmpty { missing.append(.bottom) }
        if shoes.isEmpty { missing.append(.shoes) }
        guard missing.isEmpty else {
            return Result(drafts: [], missingRequired: missing)
        }

        // 3. 冷天且有外套时自动加外套。
        let includeOuter = [.frigid, .cold, .cool].contains(warmth) && !outers.isEmpty

        // 4. 组装：通过取模错位组合，尽量产出不重复的多套。
        let count = min(maxCount, max(tops.count, bottoms.count, shoes.count))
        var drafts: [OutfitDraft] = []
        var seenKeys = Set<String>()

        for i in 0..<count {
            let top = tops[i % tops.count]
            let bottom = bottoms[i % bottoms.count]
            let shoe = shoes[i % shoes.count]
            let outer = includeOuter ? outers[i % outers.count] : nil
            let accessory = accessories.isEmpty ? nil : accessories[i % accessories.count]
            let sock = socks.isEmpty ? nil : socks[i % socks.count]

            let key = [top.id, bottom.id, shoe.id, outer?.id, accessory?.id, sock?.id]
                .map { $0?.uuidString ?? "-" }
                .joined(separator: "|")
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            drafts.append(
                OutfitDraft(
                    top: top,
                    bottom: bottom,
                    shoes: shoe,
                    outerwear: outer,
                    accessory: accessory,
                    socks: sock
                )
            )
        }

        return Result(drafts: drafts, missingRequired: [])
    }
}
