import Foundation
import ClosetCore
@testable import ClosetStorage

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("closet-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])

func makeItem(
    _ subtype: Subtype? = .tee, category: ClosetCore.Category? = nil, status: ItemStatus = .inWardrobe,
    created: TimeInterval = 1_750_000_000, processed: MediaRef? = nil, original: MediaRef? = nil
) -> StoredItem {
    let color = StoredColor(red: 0.2, green: 0.3, blue: 0.8)
    return StoredItem(
        id: UUID(), name: "测试", category: category ?? subtype!.category, subtype: subtype, scenarios: [.casual, .work],
        status: status, isWaterproof: true, laundryEntryDate: status == .inLaundry ? Date(timeIntervalSince1970: created + 10) : nil,
        dominantColor: color, secondaryColor: StoredColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.5),
        dominantColorCategory: ColorCategory.classify(color), warmthScore: 42, warmthLevels: [.mild], seasons: [.spring, .autumn],
        brand: "品牌", notes: nil, createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: created + 1),
        processedImage: processed, originalImage: original)
}
