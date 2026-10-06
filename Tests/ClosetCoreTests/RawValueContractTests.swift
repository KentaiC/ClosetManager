import XCTest
import ClosetCore

/// 枚举原始值契约。
///
/// 这些字符串同时出现在 SwiftData 持久化数据与 `.wardrobe` 备份文件中，
/// 任何改名都会让已有数据无法解码。本测试把当前取值逐字固定下来。
final class RawValueContractTests: XCTestCase {
    func testCategoryRawValues() {
        XCTAssertEqual(ClosetCore.Category.allCases.map(\.rawValue),
                       ["outerwear", "top", "bottom", "shoes", "accessory", "socks"])
    }

    func testItemStatusRawValues() {
        XCTAssertEqual(ItemStatus.allCases.map(\.rawValue), ["inWardrobe", "inLaundry", "inLuggage"])
    }

    func testScenarioRawValues() {
        XCTAssertEqual(Scenario.allCases.map(\.rawValue), ["work", "casual", "sport", "formal"])
    }

    func testWarmthLevelRawValues() {
        XCTAssertEqual(WarmthLevel.allCases.map(\.rawValue), ["frigid", "cold", "cool", "mild", "warm", "hot"])
    }

    func testSeasonRawValues() {
        XCTAssertEqual(Season.allCases.map(\.rawValue), ["spring", "summer", "autumn", "winter"])
    }

    func testOutfitSourceRawValues() {
        XCTAssertEqual(OutfitSource.allCases.map(\.rawValue), ["generated", "manual"])
    }

    func testGenderRawValues() {
        XCTAssertEqual(Gender.allCases.map(\.rawValue), ["male", "female", "other", "unspecified"])
    }

    func testColorCategoryRawValues() {
        XCTAssertEqual(ColorCategory.allCases.map(\.rawValue),
                       ["black", "white", "gray", "beige", "brown", "red", "orange", "yellow",
                        "green", "cyan", "blue", "purple", "pink", "multicolor"])
    }

    func testSubtypeRawValues() {
        XCTAssertEqual(Subtype.allCases.map(\.rawValue), [
            "jacket", "trenchCoat", "overcoat", "downJacket", "paddedJacket", "leatherJacket", "blazer", "cardigan", "vest",
            "tee", "polo", "shirt", "hoodie", "sweater", "tankTop", "baseLayer", "suit",
            "jeans", "casualPants", "dressPants", "sweatpants", "shorts", "skirt",
            "sneakers", "canvasShoes", "leatherShoes", "boots", "sandals", "slippers", "heels",
            "hat", "scarf", "belt", "bag", "gloves", "glasses", "tie", "jewelry",
            "noShowSocks", "ankleSocks", "crewSocks", "kneeSocks", "athleticSocks",
        ])
    }

    func testEnumsEncodeAsBareRawValueStrings() throws {
        let data = try JSONEncoder().encode([ClosetCore.Category.outerwear])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["outerwear"]"#)
    }

    func testStoredColorCodingKeys() throws {
        let data = try JSONEncoder().encode(StoredColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Double]
        XCTAssertEqual(object, ["red": 1, "green": 0.5, "blue": 0, "alpha": 1])
    }
}
