import XCTest
@testable import ClosetCore

final class ColorExtractionTests: XCTestCase {
    private func pixels(_ runs: [(count: Int, rgba: [UInt8])]) -> [UInt8] {
        runs.flatMap { run in Array(repeating: run.rgba, count: run.count).flatMap { $0 } }
    }

    func testFallsBackToNeutralGrayWithoutOpaquePixels() {
        let result = ColorExtraction.extract(rgba: pixels([(10, [255, 0, 0, 31])]))
        XCTAssertEqual(result.dominant, StoredColor(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertNil(result.secondary)
        XCTAssertEqual(ColorExtraction.extract(rgba: []).dominant, ColorExtraction.fallback)
    }

    func testDominantIsTheAverageOfTheLargestBucketAndSkipsTransparentPixels() {
        // 两种红色落在同一个桶里，取平均；大量透明蓝色像素不参与统计。
        let result = ColorExtraction.extract(rgba: pixels([(3, [250, 10, 10, 255]), (1, [230, 30, 30, 255]), (50, [0, 0, 255, 0])]))
        XCTAssertEqual(result.dominant.red, 245.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(result.dominant.green, 15.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(result.dominant.blue, 15.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(result.dominant.alpha, 1)
        XCTAssertNil(result.secondary)
    }

    func testSecondaryMustDifferEnoughFromDominant() {
        // 第二大的桶与主色太接近，跳过；第三大的桶差异足够，成为辅色。
        let result = ColorExtraction.extract(rgba: pixels([
            (10, [200, 200, 200, 255]),
            (6, [170, 200, 200, 255]),
            (3, [20, 20, 120, 255]),
        ]))
        XCTAssertEqual(result.dominant.hexString, "#C8C8C8")
        XCTAssertEqual(result.secondary?.hexString, "#141478")
    }

    func testTiesAreResolvedByBucketNumber() {
        // 黑色桶编号 0，白色桶编号 215；件数相同时黑色在前。
        let a = ColorExtraction.extract(rgba: pixels([(5, [255, 255, 255, 255]), (5, [0, 0, 0, 255])]))
        let b = ColorExtraction.extract(rgba: pixels([(5, [0, 0, 0, 255]), (5, [255, 255, 255, 255])]))
        XCTAssertEqual(a.dominant.hexString, "#000000")
        XCTAssertEqual(a.secondary?.hexString, "#FFFFFF")
        XCTAssertEqual(a.dominant, b.dominant)
        XCTAssertEqual(a.secondary, b.secondary)
    }

    func testIgnoresATrailingPartialPixel() {
        XCTAssertEqual(ColorExtraction.extract(rgba: [10, 20, 30, 255, 1, 2]).dominant.hexString, "#0A141E")
    }
}

final class SimilarityGroupingTests: XCTestCase {
    private let ids = (0..<5).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
    private let gray = StoredColor(red: 0.5, green: 0.5, blue: 0.5)

    func testGroupsAreTransitiveAndKeepInputOrder() {
        let colors = Dictionary(uniqueKeysWithValues: ids.map { ($0, gray) })
        // 0~2 相似，2~4 相似，于是 0、2、4 成为一组；1 与 3 不与任何单品相似。
        let close: Set<[Int]> = [[0, 2], [2, 4]]
        let groups = SimilarityGrouping.groups(ids: ids, colors: colors) { a, b in
            let pair = [ids.firstIndex(of: a)!, ids.firstIndex(of: b)!].sorted()
            return close.contains(pair) ? 0.1 : 5
        }
        XCTAssertEqual(groups, [[ids[0], ids[2], ids[4]]])
    }

    func testBothThresholdsMustPass() {
        var colors = Dictionary(uniqueKeysWithValues: ids.map { ($0, gray) })
        colors[ids[1]] = StoredColor(red: 0.9, green: 0.5, blue: 0.5)
        let groups = SimilarityGrouping.groups(ids: Array(ids.prefix(3)), colors: colors) { _, _ in 0.59 }
        XCTAssertEqual(groups, [[ids[0], ids[2]]], "the red item is visually close but its colour differs by 0.4")
        XCTAssertEqual(SimilarityGrouping.groups(ids: Array(ids.prefix(2)), colors: colors) { _, _ in 0.6 }, [])
    }

    func testMissingFeaturesOrColoursNeverMatch() {
        let colors = [ids[0]: gray, ids[1]: gray]
        XCTAssertEqual(SimilarityGrouping.groups(ids: ids, colors: colors) { _, _ in nil }, [])
        XCTAssertEqual(SimilarityGrouping.groups(ids: ids, colors: colors) { _, _ in 0 }, [[ids[0], ids[1]]])
    }

    func testDefaultThresholdsMatchTheApp() {
        XCTAssertEqual(SimilarityGrouping.featureThreshold, 0.6)
        XCTAssertEqual(SimilarityGrouping.colorThreshold, 0.30)
        XCTAssertEqual(SimilarityGrouping.colorDistance(StoredColor(red: 0, green: 0.5, blue: 1), gray), 1.0, accuracy: 1e-12)
    }
}
