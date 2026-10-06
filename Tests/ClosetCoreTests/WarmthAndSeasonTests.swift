import XCTest
import ClosetCore

final class WarmthAndSeasonTests: XCTestCase {
    func testScoreToLevelBoundaries() {
        let expectations: [(Int, WarmthLevel)] = [
            (1, .hot), (16, .hot), (17, .warm), (33, .warm), (34, .mild), (50, .mild),
            (51, .cool), (67, .cool), (68, .cold), (84, .cold), (85, .frigid), (100, .frigid),
        ]
        for (score, level) in expectations {
            XCTAssertEqual(WarmthLevel.from(score: score), level, "score \(score)")
        }
    }

    func testRepresentativeScoreMapsBackToSameLevel() {
        for level in WarmthLevel.allCases {
            XCTAssertEqual(WarmthLevel.from(score: level.representativeScore), level)
        }
    }

    func testLayeringBudgets() {
        XCTAssertEqual(WarmthLevel.allCases.map(\.torsoBudget), [170, 130, 88, 62, 40, 22])
        XCTAssertEqual(WarmthLevel.allCases.map(\.maxSingleGarmentWarmth), [100, 100, 100, 78, 58, 38])
    }

    func testSeasonDerivationIsOrderedAndDeduplicated() {
        XCTAssertEqual(Season.derive(from: [.hot]), [.summer])
        XCTAssertEqual(Season.derive(from: [.mild]), [.spring, .autumn])
        XCTAssertEqual(Season.derive(from: [.frigid, .cold]), [.autumn, .winter])
        XCTAssertEqual(Season.derive(from: [.warm, .cool]), [.spring, .summer, .autumn])
        XCTAssertEqual(Season.derive(from: []), [])
    }
}
