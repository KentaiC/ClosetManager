import XCTest
import ClosetCore

final class TravelServiceTests: XCTestCase {
    func testUnderwearCountIsOnePerDayPlusSpareCappedAtFive() {
        let counts = (0...10).map { TravelService.underwearCount(days: $0) }
        XCTAssertEqual(counts, [2, 2, 3, 4, 5, 5, 5, 5, 5, 5, 5])
        XCTAssertEqual(TravelService.packingCap, 5)
    }

    func testSocksFollowUnderwearRule() {
        for days in 0...30 {
            XCTAssertEqual(TravelService.socksCount(days: days), TravelService.underwearCount(days: days))
        }
    }

    func testCapHintShownAfterFourDays() {
        XCTAssertEqual((1...6).map { TravelService.showsCapHint(days: $0) }, [false, false, false, false, true, true])
    }
}
