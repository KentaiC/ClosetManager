import Foundation
import ClosetCore
import Hummingbird

/// 枚举与规则元数据。前端用它渲染选项与中文名称，不在 TypeScript 中重复定义。
public struct APIMeta: Codable, Sendable, ResponseEncodable {
    public struct Option: Codable, Sendable {
        public var value: String
        public var displayName: String
    }

    public struct CategoryInfo: Codable, Sendable {
        public var value: String
        public var displayName: String
        public var isRequiredInOutfit: Bool
        public var washByDefaultOnTakeOff: Bool
        public var subtypes: [Option]
    }

    public struct ScenarioInfo: Codable, Sendable {
        public var value: String
        public var displayName: String
        public var conflictsWith: [String]
    }

    public struct WarmthLevelInfo: Codable, Sendable {
        public var value: String
        public var displayName: String
        public var representativeScore: Int
        public var torsoBudget: Int
        public var maxSingleGarmentWarmth: Int
        public var seasons: [String]
    }

    public struct Rules: Codable, Sendable {
        /// 洗衣袋滞留预警天数，来自共享核心 WardrobeRules。
        public var laundryRetentionWarningDays: Int
        /// 「吃灰」判定天数，来自共享核心 WardrobeRules。
        public var unwornDays: Int
        public var travelPackingCap: Int
    }

    public var categories: [CategoryInfo]
    public var scenarios: [ScenarioInfo]
    public var statuses: [Option]
    public var warmthLevels: [WarmthLevelInfo]
    public var seasons: [Option]
    public var colorCategories: [Option]
    public var outfitSources: [Option]
    public var genders: [Option]
    public var rules: Rules

    public static let current = APIMeta(
        categories: ClosetCore.Category.allCases.map {
            CategoryInfo(value: $0.rawValue, displayName: $0.displayName, isRequiredInOutfit: $0.isRequiredInOutfit,
                         washByDefaultOnTakeOff: $0.washByDefaultOnTakeOff,
                         subtypes: $0.subtypes.map { Option(value: $0.rawValue, displayName: $0.displayName) })
        },
        scenarios: Scenario.allCases.map {
            ScenarioInfo(value: $0.rawValue, displayName: $0.displayName,
                         conflictsWith: Scenario.allCases.filter($0.conflictingScenarios.contains).map(\.rawValue))
        },
        statuses: ItemStatus.allCases.map { Option(value: $0.rawValue, displayName: $0.displayName) },
        warmthLevels: WarmthLevel.allCases.map {
            WarmthLevelInfo(value: $0.rawValue, displayName: $0.displayName, representativeScore: $0.representativeScore,
                            torsoBudget: $0.torsoBudget, maxSingleGarmentWarmth: $0.maxSingleGarmentWarmth,
                            seasons: Season.allCases.filter($0.seasons.contains).map(\.rawValue))
        },
        seasons: Season.allCases.map { Option(value: $0.rawValue, displayName: $0.displayName) },
        colorCategories: ColorCategory.allCases.map { Option(value: $0.rawValue, displayName: $0.displayName) },
        outfitSources: OutfitSource.allCases.map { Option(value: $0.rawValue, displayName: $0.displayName) },
        genders: Gender.allCases.map { Option(value: $0.rawValue, displayName: $0.displayName) },
        rules: Rules(
            laundryRetentionWarningDays: Int(WardrobeRules.laundryRetentionWarningInterval / 86_400),
            unwornDays: WardrobeRules.unwornDays,
            travelPackingCap: TravelService.packingCap)
    )
}
