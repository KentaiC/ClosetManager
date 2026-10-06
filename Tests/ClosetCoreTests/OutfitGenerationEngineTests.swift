import XCTest
import ClosetCore

final class OutfitGenerationEngineTests: XCTestCase {
    private func generate(_ items: [TestItem], _ warmth: WarmthLevel, _ scenario: Scenario = .casual,
                          waterproof: Bool = false, maxCount: Int = 8, seed: UInt64 = 1) -> OutfitGenerationResult<TestItem> {
        var rng = SplitMix64(seed: seed)
        return OutfitGenerationEngine.generate(from: items, warmth: warmth, scenario: scenario,
                                               requireWaterproof: waterproof, maxCount: maxCount, using: &rng)
    }

    // MARK: - 确定性

    func testSameSeedProducesIdenticalDrafts() {
        var meta = SplitMix64(seed: 42)
        let items = RandomWardrobe.make(&meta, size: 60)
        let a = generate(items, .cool, seed: 9)
        let b = generate(items, .cool, seed: 9)
        XCTAssertEqual(a.drafts.map { $0.allItems.map(\.id) }, b.drafts.map { $0.allItems.map(\.id) })
    }

    // MARK: - 不变量

    func testInvariantsHoldAcrossRandomWardrobes() {
        var meta = SplitMix64(seed: 2026)
        var checked = 0
        for round in 0..<300 {
            let items = RandomWardrobe.make(&meta, size: Int.random(in: 0...60, using: &meta))
            for warmth in WarmthLevel.allCases {
                for scenario in Scenario.allCases {
                    for waterproof in [false, true] {
                        let maxCount = [1, 3, 8][round % 3]
                        let result = generate(items, warmth, scenario, waterproof: waterproof, maxCount: maxCount, seed: UInt64(round))
                        if !result.missingRequired.isEmpty { XCTAssertTrue(result.drafts.isEmpty) }
                        XCTAssertLessThanOrEqual(result.drafts.count, max(maxCount, 1))
                        var keys = Set<[UUID]>()
                        for draft in result.drafts {
                            checked += 1
                            assertInvariants(draft, warmth: warmth, scenario: scenario, waterproof: waterproof)
                            XCTAssertTrue(keys.insert(draft.allItems.map(\.id)).inserted, "drafts are unique")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    private func assertInvariants(_ d: OutfitDraftOf<TestItem>, warmth: WarmthLevel, scenario: Scenario, waterproof: Bool) {
        for item in d.allItems {
            XCTAssertEqual(item.status, .inWardrobe)
            XCTAssertTrue(item.scenarios.contains(scenario))
        }
        XCTAssertEqual(d.top.category, .top)
        XCTAssertEqual(d.bottom.category, .bottom)
        XCTAssertEqual(d.shoes.category, .shoes)
        XCTAssertEqual(d.midLayer?.category ?? .top, .top)
        XCTAssertEqual(d.outerwear?.category ?? .outerwear, .outerwear)
        XCTAssertEqual(d.socks?.category ?? .socks, .socks)
        XCTAssertEqual(d.accessory?.category ?? .accessory, .accessory)
        for torso in [d.top, d.midLayer, d.outerwear].compactMap({ $0 }) {
            XCTAssertLessThanOrEqual(torso.warmthScore, warmth.maxSingleGarmentWarmth)
        }
        XCTAssertNotEqual(d.shoes.subtype, .slippers)
        if scenario == .sport {
            XCTAssertNotEqual(d.top.subtype, .suit)
            XCTAssertNotEqual(d.midLayer?.subtype, .suit)
            XCTAssertNotEqual(d.outerwear?.subtype, .blazer)
        }
        if waterproof {
            XCTAssertEqual(d.outerwear?.isWaterproof, true)
            XCTAssertTrue(d.shoes.isWaterproof)
        }
        if let mid = d.midLayer {
            XCTAssertGreaterThan(mid.warmthScore, d.top.warmthScore)
            let short: Set<Subtype> = [.tee, .polo, .tankTop]
            XCTAssertFalse(short.contains(mid.subtype ?? .shirt) && short.contains(d.top.subtype ?? .shirt))
        }
    }

    // MARK: - 必选项

    func testEmptyWardrobeReportsRequiredCategories() {
        XCTAssertEqual(generate([], .mild).missingRequired, [.top, .bottom, .shoes])
        XCTAssertEqual(generate([], .mild, waterproof: true).missingRequired, [.top, .bottom, .shoes, .outerwear])
    }

    func testSlippersNeverSatisfyShoes() {
        let items = [TestItem(.tee, warmth: 20), TestItem(.jeans), TestItem(.slippers)]
        XCTAssertEqual(generate(items, .hot).missingRequired, [.shoes])
    }

    // MARK: - 叠穿规则

    func testSingleGarmentWithinBudgetIsWornAlone() {
        let hoodie = TestItem(.hoodie, warmth: 50)
        let items = [hoodie, TestItem(.jeans), TestItem(.sneakers), TestItem(.jacket, warmth: 40)]
        let draft = try! XCTUnwrap(generate(items, .mild).drafts.first)
        XCTAssertEqual(draft.top.id, hoodie.id)
        XCTAssertNil(draft.midLayer)
        XCTAssertNil(draft.outerwear)
    }

    func testOuterwearAddedWhenTorsoIsTooCold() {
        let tee = TestItem(.tee, warmth: 20)
        let coat = TestItem(.overcoat, warmth: 80)
        let draft = try! XCTUnwrap(generate([tee, coat, TestItem(.jeans), TestItem(.boots)], .cold).drafts.first)
        XCTAssertEqual(draft.top.id, tee.id)
        XCTAssertEqual(draft.outerwear?.id, coat.id)
    }

    func testRainRequiresWaterproofOuterwearAndShoes() {
        let items = [TestItem(.tee, warmth: 20), TestItem(.jeans),
                     TestItem(.sneakers), TestItem(.boots, waterproof: true),
                     TestItem(.jacket, warmth: 30), TestItem(.trenchCoat, warmth: 35, waterproof: true)]
        let drafts = generate(items, .hot, waterproof: true).drafts
        XCTAssertFalse(drafts.isEmpty)
        for d in drafts {
            XCTAssertEqual(d.outerwear?.subtype, .trenchCoat)
            XCTAssertEqual(d.shoes.subtype, .boots)
        }
    }

    // MARK: - 已知行为的特征记录（审计报告中的问题，修复前保持现状）

    /// 审计 H-01：未勾选场景的单品不进入任何生成池。
    func testItemsWithoutScenariosAreExcluded_AuditH01() {
        let items = [TestItem(.tee, scenarios: []), TestItem(.jeans, scenarios: []), TestItem(.sneakers, scenarios: [])]
        XCTAssertEqual(generate(items, .mild).missingRequired, [.top, .bottom, .shoes])
    }

    /// 审计 H-02：下装与鞋子不受天气约束，严寒天也会选中短裤与凉鞋。
    func testBottomsAndShoesIgnoreWeather_AuditH02() {
        let items = [TestItem(.sweater, warmth: 90), TestItem(.downJacket, warmth: 100),
                     TestItem(.shorts, warmth: 5), TestItem(.sandals, warmth: 5)]
        let draft = try! XCTUnwrap(generate(items, .frigid).drafts.first)
        XCTAssertEqual(draft.bottom.subtype, .shorts)
        XCTAssertEqual(draft.shoes.subtype, .sandals)
    }

    /// 审计 M-07：中层找不到不超预算加 25 的上装时，回退到最暖的一件。
    func testMidLayerFallbackPicksWarmest_AuditM07() {
        let tee = TestItem(.tee, warmth: 24), sweater = TestItem(.sweater, warmth: 45), hoodie = TestItem(.hoodie, warmth: 58)
        let draft = try! XCTUnwrap(generate([tee, sweater, hoodie, TestItem(.jeans), TestItem(.sneakers)], .warm).drafts.first)
        XCTAssertEqual(draft.top.id, tee.id)
        XCTAssertEqual(draft.midLayer?.id, hoodie.id)
    }

    // MARK: - 草稿结构

    func testAllItemsOrderIsOuterToInnerTopToBottom() {
        let o = TestItem(.jacket), m = TestItem(.sweater), t = TestItem(.tee), b = TestItem(.jeans)
        let s = TestItem(.crewSocks), sh = TestItem(.sneakers), a = TestItem(.hat)
        let draft = OutfitDraftOf(top: t, midLayer: m, bottom: b, shoes: sh, outerwear: o, accessory: a, socks: s)
        XCTAssertEqual(draft.allItems.map(\.id), [o, m, t, b, s, sh, a].map(\.id))
        XCTAssertEqual(OutfitDraftOf(top: t, bottom: b, shoes: sh).allItems.map(\.id), [t, b, sh].map(\.id))
    }
}
