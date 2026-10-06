import Foundation
import ClosetCore

/// 固定种子的随机数生成器，用于得到可复现的生成结果。
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 测试用单品，字段与 App 的 ClothingItem 一致。
struct TestItem: WardrobeItemRepresentable, Hashable {
    var id = UUID()
    var category: ClosetCore.Category
    var subtype: Subtype?
    var scenarios: [Scenario] = [.casual]
    var status: ItemStatus = .inWardrobe
    var isWaterproof = false
    var warmthScore = 50
    var dominantColorCategory: ColorCategory = .gray

    init(_ subtype: Subtype, warmth: Int = 50, scenarios: [Scenario] = [.casual],
         status: ItemStatus = .inWardrobe, waterproof: Bool = false, color: ColorCategory = .gray) {
        self.category = subtype.category
        self.subtype = subtype
        self.scenarios = scenarios
        self.status = status
        self.isWaterproof = waterproof
        self.warmthScore = warmth
        self.dominantColorCategory = color
    }

    init(category: ClosetCore.Category, warmth: Int = 50, scenarios: [Scenario] = [.casual]) {
        self.category = category
        self.subtype = nil
        self.scenarios = scenarios
        self.warmthScore = warmth
    }
}

struct TestRecord: WearRecordRepresentable {
    var date: Date
    var items: [TestItem]
}

enum RandomWardrobe {
    static func make(_ rng: inout SplitMix64, size: Int) -> [TestItem] {
        (0..<size).map { _ in
            let subtype = Subtype.allCases.randomElement(using: &rng)!
            var item = TestItem(
                subtype,
                warmth: Int.random(in: 1...100, using: &rng),
                scenarios: Scenario.allCases.filter { _ in Bool.random(using: &rng) },
                status: Int.random(in: 0..<6, using: &rng) == 0 ? .inLaundry : .inWardrobe,
                waterproof: Int.random(in: 0..<3, using: &rng) == 0
            )
            if Int.random(in: 0..<5, using: &rng) == 0 { item.subtype = nil }
            return item
        }
    }
}
