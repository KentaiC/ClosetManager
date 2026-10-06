import XCTest
import ClosetCore

final class ColorRulesTests: XCTestCase {
    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> StoredColor {
        StoredColor(red: r / 255, green: g / 255, blue: b / 255)
    }

    func testHSBOfPrimaries() {
        XCTAssertEqual(rgb(255, 0, 0).hsb.hue, 0, accuracy: 1e-9)
        XCTAssertEqual(rgb(0, 255, 0).hsb.hue, 120, accuracy: 1e-9)
        XCTAssertEqual(rgb(0, 0, 255).hsb.hue, 240, accuracy: 1e-9)
        XCTAssertEqual(rgb(255, 0, 255).hsb.hue, 300, accuracy: 1e-9)
        XCTAssertEqual(rgb(0, 0, 0).hsb.saturation, 0)
        XCTAssertEqual(rgb(128, 128, 128).hsb.saturation, 0)
    }

    func testHexString() {
        XCTAssertEqual(rgb(26, 43, 60).hexString, "#1A2B3C")
        XCTAssertEqual(StoredColor(red: 0.5, green: 0.5, blue: 0.5).hexString, "#808080")
    }

    /// 以 ColorNaming 参考色为输入，固定当前「粗分类」与「精细色名」两套体系的输出。
    /// 其中 驼色、桃粉、橄榄绿 等行记录的是审计报告 M-16 所述的现有不一致，不代表期望行为。
    func testClassificationAndNamingOfReferenceColors() {
        let table: [(name: String, r: Double, g: Double, b: Double, bucket: ColorCategory)] = [
            ("黑色", 20, 20, 22, .black), ("白色", 245, 245, 245, .white), ("浅灰", 200, 200, 202, .gray),
            ("灰色", 130, 130, 134, .gray), ("深灰", 70, 72, 78, .gray), ("米白", 238, 232, 218, .white),
            ("米色", 222, 208, 178, .beige), ("卡其", 195, 176, 145, .beige), ("驼色", 181, 145, 102, .orange),
            ("棕色", 120, 80, 50, .brown), ("咖啡", 78, 54, 41, .brown), ("酒红", 110, 30, 45, .red),
            ("正红", 200, 40, 45, .red), ("砖红", 170, 70, 55, .red), ("粉色", 235, 170, 190, .pink),
            ("桃粉", 240, 150, 140, .red), ("橙色", 232, 130, 50, .orange), ("姜黄", 205, 150, 40, .orange),
            ("黄色", 235, 205, 70, .yellow), ("米黄", 230, 222, 160, .yellow), ("草绿", 110, 180, 80, .green),
            ("墨绿", 35, 80, 60, .green), ("橄榄绿", 110, 120, 60, .yellow), ("军绿", 90, 100, 70, .green),
            ("青色", 70, 175, 170, .cyan), ("天蓝", 120, 180, 225, .blue), ("蓝色", 50, 100, 200, .blue),
            ("海军蓝", 40, 70, 130, .blue), ("藏青", 30, 40, 80, .blue), ("紫色", 130, 80, 175, .purple),
            ("深紫", 80, 50, 110, .purple),
        ]
        for row in table {
            let color = rgb(row.r, row.g, row.b)
            XCTAssertEqual(ColorNaming.name(for: color), row.name)
            XCTAssertEqual(color.refinedColorName, row.name)
            XCTAssertEqual(ColorCategory.classify(color), row.bucket, row.name)
        }
    }

    func testMulticolorBucketIsNeverProducedByClassify() {
        var produced = Set<ColorCategory>()
        for r in stride(from: 0.0, through: 255, by: 15) {
            for g in stride(from: 0.0, through: 255, by: 15) {
                for b in stride(from: 0.0, through: 255, by: 15) {
                    produced.insert(ColorCategory.classify(rgb(r, g, b)))
                }
            }
        }
        XCTAssertFalse(produced.contains(.multicolor))
        XCTAssertEqual(produced, Set(ColorCategory.allCases).subtracting([.multicolor]))
    }
}
