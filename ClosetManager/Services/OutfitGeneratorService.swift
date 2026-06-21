import Foundation

/// 一套穿搭草稿（尚未持久化）。支持躯干叠穿：基础上装 +（可选）中间层 +（可选）外套。
///
/// 结构：[外套(可选)] + [中间层(可选,另一件上装)] + [上装(必选,最内层打底)]
///       + [下装(必选)] + [鞋子(必选)] + [袜子(可选)] + [配饰(可选)]。
struct OutfitDraft: Identifiable {
    let id = UUID()
    var top: ClothingItem          // 基础上装（最内层打底，必选）
    var midLayer: ClothingItem? = nil  // 中间层（另一件上装，如卫衣/毛衣）
    var bottom: ClothingItem
    var shoes: ClothingItem
    var outerwear: ClothingItem?
    var accessory: ClothingItem?
    var socks: ClothingItem?

    /// 全部单品（由外到内、自上而下排序，便于展示）。
    var allItems: [ClothingItem] {
        [outerwear, midLayer, top, bottom, socks, shoes, accessory].compactMap { $0 }
    }
}

/// 本地穿搭生成引擎（纯函数，与 UI 解耦）。引入保暖度求和与叠穿约束。
enum OutfitGeneratorService {
    struct Result {
        var drafts: [OutfitDraft]
        var missingRequired: [Category]
    }

    /// 根据「当前天气档位 + 场景」生成多套叠穿穿搭。
    /// - Parameter requireWaterproof: 雨雪天气强关联——为 true 时强制外套与鞋子必须防水，且外套必选。
    static func generate(
        from items: [ClothingItem],
        warmth: WarmthLevel,
        scenario: Scenario,
        requireWaterproof: Bool = false,
        maxCount: Int = 8
    ) -> Result {
        let budget = warmth.torsoBudget
        let maxSingle = warmth.maxSingleGarmentWarmth
        // 运动场景：禁止正式属性单品（西装 / 西装外套）混入。
        let banFormal = (scenario == .sport)
        // 雨雪天：外套必选。
        let requireOuter = requireWaterproof

        // 基础可用池：在衣橱中 + 匹配场景。
        func available(_ category: Category) -> [ClothingItem] {
            items.filter { $0.isAvailable && $0.category == category && $0.scenarios.contains(scenario) }
        }

        // 躯干层（上装 / 外套）额外受「气温向下兼容」上限约束：过暖单品在炎热天被排除。
        let tops = available(.top)
            .filter { $0.warmthScore <= maxSingle && !(banFormal && $0.subtype == .suit) }
            .shuffled()
        let outers = available(.outerwear)
            .filter {
                $0.warmthScore <= maxSingle
                && !(banFormal && $0.subtype == .blazer)
                && (!requireWaterproof || $0.isWaterproof)   // 雨雪天外套必须防水
            }
            .shuffled()

        let bottoms = available(.bottom).shuffled()
        // 拖鞋绝不进日常穿搭；雨雪天鞋子必须防水。
        let shoes = available(.shoes)
            .filter { $0.subtype != .slippers && (!requireWaterproof || $0.isWaterproof) }
            .shuffled()
        let accessories = available(.accessory).shuffled()
        let socks = available(.socks).shuffled()

        // 必选分类校验。
        var missing: [Category] = []
        if tops.isEmpty { missing.append(.top) }
        if bottoms.isEmpty { missing.append(.bottom) }
        if shoes.isEmpty { missing.append(.shoes) }
        if requireOuter && outers.isEmpty { missing.append(.outerwear) }
        guard missing.isEmpty else { return Result(drafts: [], missingRequired: missing) }

        var drafts: [OutfitDraft] = []
        var seenKeys = Set<String>()
        let attempts = min(maxCount, max(tops.count, bottoms.count, shoes.count))

        for seed in 0..<max(attempts, 1) {
            guard let layers = buildTorso(tops: tops, outers: outers, budget: budget, seed: seed, requireOuter: requireOuter) else { continue }
            let bottom = bottoms[seed % bottoms.count]
            let shoe = shoes[seed % shoes.count]
            let accessory = accessories.isEmpty ? nil : accessories[seed % accessories.count]
            let sock = socks.isEmpty ? nil : socks[seed % socks.count]

            let key = [layers.base.id, layers.mid?.id, layers.outer?.id, bottom.id, shoe.id, accessory?.id, sock?.id]
                .map { $0?.uuidString ?? "-" }
                .joined(separator: "|")
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            drafts.append(
                OutfitDraft(
                    top: layers.base,
                    midLayer: layers.mid,
                    bottom: bottom,
                    shoes: shoe,
                    outerwear: layers.outer,
                    accessory: accessory,
                    socks: sock
                )
            )
        }

        return Result(drafts: drafts, missingRequired: [])
    }

    // MARK: - 躯干叠穿构建

    /// 依据保暖度预算堆叠躯干层，返回 (基础上装, 中间层?, 外套?)。
    ///
    /// 规则：
    /// - 优先用「不超预算的最暖单件上装」单穿；不够暖再加中间层 / 外套堆叠求和。
    /// - 同类排斥：基础层与中间层不可同为短袖。
    /// - 基础打底：外套始终建立在一件上装之上（base 必为上装），外套绝不单穿。
    private static func buildTorso(
        tops: [ClothingItem],
        outers: [ClothingItem],
        budget: Int,
        seed: Int,
        requireOuter: Bool = false
    ) -> (base: ClothingItem, mid: ClothingItem?, outer: ClothingItem?)? {
        guard !tops.isEmpty else { return nil }
        let sortedTops = tops.sorted { $0.warmthScore < $1.warmthScore }

        // 基础上装：优先「不超预算的最暖上装」，并用 seed 轮换增加多样性。
        let underBudget = sortedTops.filter { $0.warmthScore <= budget }
        let basePool = Array((underBudget.isEmpty ? sortedTops : underBudget).reversed()) // 暖→冷
        let base = basePool[seed % basePool.count]
        var sum = base.warmthScore
        var mid: ClothingItem?
        var outer: ClothingItem?

        // 不够暖 → 加中间层（更暖的另一件上装，且与 base 不同时为短袖）。
        if sum < budget - 15 {
            let midCandidates = sortedTops.filter {
                $0.id != base.id
                && $0.warmthScore > base.warmthScore
                && !(isShortSleeve($0) && isShortSleeve(base))
            }
            if let chosen = midCandidates.first(where: { sum + $0.warmthScore <= budget + 25 }) ?? midCandidates.last {
                mid = chosen
                sum += chosen.warmthScore
            }
        }

        // 仍不够暖、或雨雪天强制要求时 → 加外套（外套之上不再叠外套，天然满足"同级别厚外套不叠两件"）。
        if (sum < budget - 15 || requireOuter), !outers.isEmpty {
            let sortedOuters = outers.sorted { $0.warmthScore < $1.warmthScore }
            if let chosen = sortedOuters.first(where: { sum + $0.warmthScore >= budget - 20 }) ?? sortedOuters.last {
                outer = chosen
                sum += chosen.warmthScore
            }
        }

        // 雨雪天强制外套但没选上 → 此套作废。
        if requireOuter && outer == nil { return nil }

        return (base, mid, outer)
    }

    /// 是否为短袖类上装（用于同类排斥）。
    private static func isShortSleeve(_ item: ClothingItem) -> Bool {
        guard item.category == .top, let subtype = item.subtype else { return false }
        return [.tee, .polo, .tankTop].contains(subtype)
    }
}
