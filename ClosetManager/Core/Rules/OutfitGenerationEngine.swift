import Foundation

/// 一套穿搭草稿（尚未持久化）。支持躯干叠穿：基础上装 +（可选）中间层 +（可选）外套。
///
/// 结构：[外套(可选)] + [中间层(可选,另一件上装)] + [上装(必选,最内层打底)]
///       + [下装(必选)] + [鞋子(必选)] + [袜子(可选)] + [配饰(可选)]。
///
/// 泛型参数 `Item` 是单品类型：App 端为 `ClothingItem`，服务端为其单品记录。
public struct OutfitDraftOf<Item>: Identifiable {
    public let id = UUID()
    public var top: Item          // 基础上装（最内层打底，必选）
    public var midLayer: Item?    // 中间层（另一件上装，如卫衣/毛衣）
    public var bottom: Item
    public var shoes: Item
    public var outerwear: Item?
    public var accessory: Item?
    public var socks: Item?

    public init(
        top: Item,
        midLayer: Item? = nil,
        bottom: Item,
        shoes: Item,
        outerwear: Item? = nil,
        accessory: Item? = nil,
        socks: Item? = nil
    ) {
        self.top = top
        self.midLayer = midLayer
        self.bottom = bottom
        self.shoes = shoes
        self.outerwear = outerwear
        self.accessory = accessory
        self.socks = socks
    }

    /// 全部单品（由外到内、自上而下排序，便于展示）。
    public var allItems: [Item] {
        [outerwear, midLayer, top, bottom, socks, shoes, accessory].compactMap { $0 }
    }
}

extension OutfitDraftOf: Sendable where Item: Sendable {}

/// 穿搭生成结果：生成的草稿，或缺失的必选分类。
public struct OutfitGenerationResult<Item> {
    public var drafts: [OutfitDraftOf<Item>]
    public var missingRequired: [Category]

    public init(drafts: [OutfitDraftOf<Item>], missingRequired: [Category]) {
        self.drafts = drafts
        self.missingRequired = missingRequired
    }
}

extension OutfitGenerationResult: Sendable where Item: Sendable {}

/// 本地穿搭生成引擎（纯函数，与 UI 和持久化解耦）。引入保暖度求和与叠穿约束。
///
/// 随机性只来自传入的随机数生成器：不传时使用系统随机源，与重构前的 `shuffled()` 行为一致；
/// 测试可传入固定种子的生成器得到可复现结果。
public enum OutfitGenerationEngine {

    /// 使用系统随机源生成。
    public static func generate<Item: WardrobeItemRepresentable>(
        from items: [Item],
        warmth: WarmthLevel,
        scenario: Scenario,
        requireWaterproof: Bool = false,
        maxCount: Int = 8
    ) -> OutfitGenerationResult<Item> {
        var rng = SystemRandomNumberGenerator()
        return generate(
            from: items,
            warmth: warmth,
            scenario: scenario,
            requireWaterproof: requireWaterproof,
            maxCount: maxCount,
            using: &rng
        )
    }

    /// 根据「当前天气档位 + 场景」生成多套叠穿穿搭。
    /// - Parameter requireWaterproof: 雨雪天气强关联——为 true 时强制外套与鞋子必须防水，且外套必选。
    /// - Parameter rng: 随机数生成器，决定各候选池的洗牌顺序。
    public static func generate<Item: WardrobeItemRepresentable, G: RandomNumberGenerator>(
        from items: [Item],
        warmth: WarmthLevel,
        scenario: Scenario,
        requireWaterproof: Bool = false,
        maxCount: Int = 8,
        using rng: inout G
    ) -> OutfitGenerationResult<Item> {
        let budget = warmth.torsoBudget
        let maxSingle = warmth.maxSingleGarmentWarmth
        // 运动场景：禁止正式属性单品（西装 / 西装外套）混入。
        let banFormal = (scenario == .sport)
        // 雨雪天：外套必选。
        let requireOuter = requireWaterproof

        // 基础可用池：在衣橱中 + 匹配场景。「在衣橱中」与 App 的 `ClothingItem.isAvailable` 定义相同。
        func available(_ category: Category) -> [Item] {
            items.filter { $0.status == .inWardrobe && $0.category == category && $0.scenarios.contains(scenario) }
        }

        // 躯干层（上装 / 外套）额外受「气温向下兼容」上限约束：过暖单品在炎热天被排除。
        // 洗牌顺序与重构前保持一致：上装、外套、下装、鞋子、配饰、袜子。
        let tops = available(.top)
            .filter { $0.warmthScore <= maxSingle && !(banFormal && $0.subtype == .suit) }
            .shuffled(using: &rng)
        let outers = available(.outerwear)
            .filter {
                $0.warmthScore <= maxSingle
                && !(banFormal && $0.subtype == .blazer)
                && (!requireWaterproof || $0.isWaterproof)   // 雨雪天外套必须防水
            }
            .shuffled(using: &rng)

        let bottoms = available(.bottom).shuffled(using: &rng)
        // 拖鞋绝不进日常穿搭；雨雪天鞋子必须防水。
        let shoes = available(.shoes)
            .filter { $0.subtype != .slippers && (!requireWaterproof || $0.isWaterproof) }
            .shuffled(using: &rng)
        let accessories = available(.accessory).shuffled(using: &rng)
        let socks = available(.socks).shuffled(using: &rng)

        // 必选分类校验。
        var missing: [Category] = []
        if tops.isEmpty { missing.append(.top) }
        if bottoms.isEmpty { missing.append(.bottom) }
        if shoes.isEmpty { missing.append(.shoes) }
        if requireOuter && outers.isEmpty { missing.append(.outerwear) }
        guard missing.isEmpty else { return OutfitGenerationResult(drafts: [], missingRequired: missing) }

        var drafts: [OutfitDraftOf<Item>] = []
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
                OutfitDraftOf(
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

        return OutfitGenerationResult(drafts: drafts, missingRequired: [])
    }

    // MARK: - 躯干叠穿构建

    /// 依据保暖度预算堆叠躯干层，返回 (基础上装, 中间层?, 外套?)。
    ///
    /// 规则：
    /// - 优先用「不超预算的最暖单件上装」单穿；不够暖再加中间层 / 外套堆叠求和。
    /// - 同类排斥：基础层与中间层不可同为短袖。
    /// - 基础打底：外套始终建立在一件上装之上（base 必为上装），外套绝不单穿。
    private static func buildTorso<Item: WardrobeItemRepresentable>(
        tops: [Item],
        outers: [Item],
        budget: Int,
        seed: Int,
        requireOuter: Bool = false
    ) -> (base: Item, mid: Item?, outer: Item?)? {
        guard !tops.isEmpty else { return nil }
        let sortedTops = tops.sorted { $0.warmthScore < $1.warmthScore }

        // 基础上装：优先「不超预算的最暖上装」，并用 seed 轮换增加多样性。
        let underBudget = sortedTops.filter { $0.warmthScore <= budget }
        let basePool = Array((underBudget.isEmpty ? sortedTops : underBudget).reversed()) // 暖→冷
        let base = basePool[seed % basePool.count]
        var sum = base.warmthScore
        var mid: Item?
        var outer: Item?

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
    private static func isShortSleeve<Item: WardrobeItemRepresentable>(_ item: Item) -> Bool {
        guard item.category == .top, let subtype = item.subtype else { return false }
        return [.tee, .polo, .tankTop].contains(subtype)
    }
}
