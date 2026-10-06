import XCTest
import ClosetCore

final class CategoryRulesTests: XCTestCase {
    func testEverySubtypeBelongsToExactlyOneCategoryAndPartitionIsComplete() {
        let fromCategories = ClosetCore.Category.allCases.flatMap(\.subtypes)
        XCTAssertEqual(Set(fromCategories), Set(Subtype.allCases))
        XCTAssertEqual(fromCategories.count, Subtype.allCases.count)
        for subtype in Subtype.allCases {
            XCTAssertTrue(subtype.category.subtypes.contains(subtype))
        }
    }

    func testSubtypeCountsPerCategory() {
        let counts = Dictionary(uniqueKeysWithValues: ClosetCore.Category.allCases.map { ($0, $0.subtypes.count) })
        XCTAssertEqual(counts, [.outerwear: 9, .top: 8, .bottom: 6, .shoes: 7, .accessory: 8, .socks: 5])
    }

    func testRequiredSlots() {
        XCTAssertEqual(ClosetCore.Category.allCases.filter(\.isRequiredInOutfit), [.top, .bottom, .shoes])
    }

    func testWashByDefaultOnTakeOff() {
        XCTAssertEqual(ClosetCore.Category.allCases.filter(\.washByDefaultOnTakeOff), [.top, .bottom, .socks])
    }

    func testScenarioConflictsAreSymmetric() {
        XCTAssertEqual(Scenario.formal.conflictingScenarios, [.sport])
        XCTAssertEqual(Scenario.sport.conflictingScenarios, [.formal])
        XCTAssertEqual(Scenario.work.conflictingScenarios, [])
        XCTAssertEqual(Scenario.casual.conflictingScenarios, [])
        for a in Scenario.allCases {
            for b in a.conflictingScenarios {
                XCTAssertTrue(b.conflictingScenarios.contains(a))
            }
        }
    }

    func testDisplayNamesAreNonEmpty() {
        XCTAssertFalse(ClosetCore.Category.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(Subtype.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(Scenario.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(ItemStatus.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(WarmthLevel.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(Season.allCases.contains { $0.displayName.isEmpty })
        XCTAssertFalse(ColorCategory.allCases.contains { $0.displayName.isEmpty })
    }
}
