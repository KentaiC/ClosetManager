import Foundation
import ClosetCore
import ClosetStorage
@testable import ClosetServices

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

let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)

func makeStore() throws -> ClosetStore {
    try ClosetStore(inMemoryWithMediaRoot: FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString)"))
}

func storedItem(_ subtype: Subtype, status: ItemStatus = .inWardrobe, scenarios: [Scenario] = [.casual], warmth: Int = 40,
                laundry: Date? = nil, waterproof: Bool = false, color: StoredColor = StoredColor(red: 0.1, green: 0.2, blue: 0.7),
                created: TimeInterval = 1_750_000_000) -> StoredItem {
    StoredItem(id: UUID(), name: "", category: subtype.category, subtype: subtype, scenarios: scenarios, status: status,
               isWaterproof: waterproof, laundryEntryDate: laundry, dominantColor: color, secondaryColor: nil,
               dominantColorCategory: ColorCategory.classify(color), warmthScore: warmth,
               warmthLevels: [WarmthLevel.from(score: warmth)], seasons: [], brand: nil, notes: nil,
               createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: created),
               processedImage: nil, originalImage: nil)
}

func insert(_ store: ClosetStore, _ items: [StoredItem]) async throws {
    try await store.transaction { s in for item in items { try s.insertItem(item) } }
}

func expectServiceError(_ expected: ServiceError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as ServiceError {
        switch (expected, error) {
        case (.notFound, .notFound), (.conflict, .conflict), (.invalid, .invalid): break
        default: XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}

import XCTest
