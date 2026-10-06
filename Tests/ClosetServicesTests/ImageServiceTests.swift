import XCTest
import ClosetCore
import ClosetStorage
@testable import ClosetServices

final class ImageInspectorTests: XCTestCase {
    func testReadsDimensionsOfEveryAcceptedFormat() {
        XCTAssertEqual(ImageInspector.inspect(SampleImages.png(width: 640, height: 480)), .init(format: .png, width: 640, height: 480))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.jpeg(width: 4032, height: 3024)), .init(format: .jpeg, width: 4032, height: 3024))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.jpeg(width: 800, height: 600, frameMarker: 0xC2))?.width, 800, "progressive")
        XCTAssertEqual(ImageInspector.inspect(SampleImages.webpLossy(width: 300, height: 200)), .init(format: .webp, width: 300, height: 200))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.webpLossless(width: 1000, height: 16000)), .init(format: .webp, width: 1000, height: 16000))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.webpExtended(width: 5000, height: 1)), .init(format: .webp, width: 5000, height: 1))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.heic(width: 4032, height: 3024)), .init(format: .heic, width: 4032, height: 3024))
        XCTAssertEqual(ImageInspector.inspect(SampleImages.heic(width: 100, height: 100, brand: "mif1"))?.format, .heif)
    }

    func testReadsTheSampleBackupImages() throws {
        // Tests/Fixtures 中样例备份里的 1×1 PNG。
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        XCTAssertEqual(ImageInspector.inspect(png), .init(format: .png, width: 1, height: 1))
    }

    func testRejectsTruncatedOrUnknownData() {
        XCTAssertNil(ImageInspector.inspect(SampleImages.png(width: 10, height: 10).prefix(20)))
        XCTAssertNil(ImageInspector.inspect(Data([0xFF, 0xD8, 0xFF, 0xDA, 0, 4, 0, 0])), "scan before any frame header")
        XCTAssertNil(ImageInspector.inspect(SampleImages.jpeg(width: 10, height: 10, frameMarker: 0xC4).prefix(30)))
        XCTAssertNil(ImageInspector.inspect(SampleImages.png(width: 0, height: 10)))
        XCTAssertNil(ImageInspector.inspect(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)))
        XCTAssertNil(ImageInspector.inspect(Data([0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0])), "HEIC without ispe")
        XCTAssertNil(ImageInspector.inspect(Data()))
    }
}

final class ImageServiceTests: XCTestCase {
    private func makeService(_ processor: any ImageProcessor = FakeImageProcessor()) throws -> (ImageService, ClosetStore) {
        let store = try makeStore()
        return (ImageService(store: store, processor: processor, now: { fixedNow }), store)
    }

    func testUploadStoresTheExactBytesAndRecordsTheUpload() async throws {
        let (service, store) = try makeService()
        let data = SampleImages.jpeg(width: 4032, height: 3024)
        let uploaded = try await service.upload(data)
        XCTAssertEqual(uploaded.width, 4032)
        XCTAssertEqual(uploaded.ref.format, .jpeg)
        XCTAssertEqual(try store.media.read(uploaded.ref), data, "originals are kept byte for byte, metadata included (D4)")
        try await store.collectUnreferencedMedia(now: fixedNow)
        XCTAssertEqual(store.media.storedHashes(), [uploaded.ref.sha256], "kept during the grace period")
        let found = try await service.media(sha256: uploaded.ref.sha256)
        XCTAssertEqual(found, uploaded.ref)
    }

    func testUploadValidation() async throws {
        let (service, _) = try makeService()
        await expectServiceError(.invalid("")) { _ = try await service.upload(Data()) }
        await expectServiceError(.invalid("")) { _ = try await service.upload(Data("<svg onload=\"alert(1)\"/>".utf8)) }
        await expectServiceError(.invalid("")) { _ = try await service.upload(Data("GIF89a\u{1}\u{0}\u{1}\u{0}".utf8)) }
        await expectServiceError(.invalid("")) { _ = try await service.upload(SampleImages.png(width: 10, height: 10).prefix(18)) }
        await expectServiceError(.invalid("")) { _ = try await service.upload(SampleImages.png(width: 20_000, height: 20_000)) }
        var oversized = SampleImages.png(width: 10, height: 10)
        oversized.append(Data(count: ImageService.maxUploadBytes))
        await expectServiceError(.invalid("")) { _ = try await service.upload(oversized) }
        _ = try await service.upload(SampleImages.png(width: 10_000, height: 10_000))
    }

    func testMediaLookupRejectsMalformedHashes() async throws {
        let (service, _) = try makeService()
        await expectServiceError(.notFound("")) { _ = try await service.media(sha256: "../../etc/passwd") }
        await expectServiceError(.notFound("")) { _ = try await service.media(sha256: String(repeating: "A", count: 64)) }
        await expectServiceError(.notFound("")) { _ = try await service.media(sha256: String(repeating: "a", count: 64)) }
    }

    func testProcessingTakesColoursFromTheCutoutLikeTheApp() async throws {
        let processor = FakeImageProcessor()
        let (service, store) = try makeService(processor)
        let original = try await service.upload(SampleImages.jpeg(width: 100, height: 100))
        let result = try await service.process(sha256: original.ref.sha256)
        let processed = try XCTUnwrap(result.processed)
        XCTAssertEqual(processed.format, .png)
        XCTAssertEqual(result.colors?.dominant, FakeImageProcessor.processedColor)
        XCTAssertNil(result.failure)
        try await store.collectUnreferencedMedia(now: fixedNow)
        XCTAssertTrue(store.media.storedHashes().contains(processed.sha256), "the cutout is also protected until it is saved")
    }

    func testFailedCutoutFallsBackToTheOriginalForColours() async throws {
        let processor = FakeImageProcessor()
        processor.failRemoval = true
        let (service, _) = try makeService(processor)
        let original = try await service.upload(SampleImages.jpeg(width: 100, height: 100))
        let result = try await service.process(sha256: original.ref.sha256)
        XCTAssertNil(result.processed)
        XCTAssertEqual(result.colors?.dominant, FakeImageProcessor.originalColor)
        XCTAssertEqual(result.failure, "未能识别到衣物主体，请换一张主体清晰、背景简单的图片。")
    }

    func testWithoutImageFrameworksNothingIsProcessed() async throws {
        let (service, _) = try makeService(UnavailableImageProcessor())
        let original = try await service.upload(SampleImages.heic(width: 100, height: 100))
        let result = try await service.process(sha256: original.ref.sha256)
        XCTAssertNil(result.processed)
        XCTAssertNil(result.colors)
        XCTAssertNil(result.failure)
        let served = try await service.servable(original.ref, kind: .display)
        XCTAssertEqual(served, original.ref, "HEIC is served as is when it cannot be converted")
        await expectServiceError(.conflict("")) { _ = try await service.similarGroups() }
    }

    func testDerivedImagesAreGeneratedOnceAndCached() async throws {
        let processor = FakeImageProcessor()
        let (service, store) = try makeService(processor)
        let heic = try await service.upload(SampleImages.heic(width: 4032, height: 3024)).ref
        let png = try await service.upload(SampleImages.png(width: 100, height: 100)).ref

        let display = try await service.servable(heic, kind: .display)
        XCTAssertEqual(display.format, .jpeg)
        let again = try await service.servable(heic, kind: .display)
        XCTAssertEqual(again, display)
        XCTAssertEqual(processor.calls("makeDerivedImage-\(ImageService.displayPixelSize)"), 1)

        let pngDisplay = try await service.servable(png, kind: .display)
        XCTAssertEqual(pngDisplay, png, "displayable formats are not converted")
        let thumbnail = try await service.servable(png, kind: .thumbnail)
        XCTAssertNotEqual(thumbnail, png)
        XCTAssertEqual(processor.calls("makeDerivedImage-\(ImageService.thumbnailPixelSize)"), 1)
        let cached = try await store.read { try $0.variant(of: png.sha256, kind: .thumbnail) }
        XCTAssertEqual(cached, thumbnail)
    }

    func testSimilarGroupsAreReturnedAsItems() async throws {
        let processor = FakeImageProcessor()
        let (service, store) = try makeService(processor)
        let a = storedItem(.tee, created: 3), b = storedItem(.tee, created: 2), c = storedItem(.jeans, created: 1)
        try await insert(store, [a, b, c])
        processor.groups = [[a.id, b.id], [c.id, UUID()]]
        let groups = try await service.similarGroups()
        XCTAssertEqual(groups.map { $0.map(\.id) }, [[a.id, b.id]], "groups that lose members below two are dropped")
    }
}

final class ItemCreationTests: XCTestCase {
    private func edit(images: ImageChange?, name: String = "", status: ItemStatus = .inWardrobe) -> ItemEdit {
        ItemEdit(name: name, category: .top, subtype: .tee, scenarios: [.work, .casual], warmthScore: 50, seasons: [],
                 status: status, isWaterproof: false, brand: "", notes: "", dominantColor: StoredColor(red: 0.9, green: 0.1, blue: 0.1),
                 images: images)
    }

    func testCreatesAnItemLikeMakeNewItem() async throws {
        let store = try makeStore()
        let images = ImageService(store: store, processor: FakeImageProcessor(), now: { fixedNow })
        let original = try await images.upload(SampleImages.jpeg(width: 100, height: 100)).ref
        let processed = try await images.process(sha256: original.sha256).processed
        let secondary = StoredColor(red: 0, green: 0, blue: 0)
        let item = try await ItemService(store: store, now: { fixedNow }).create(
            edit(images: ImageChange(originalSHA256: original.sha256, processedSHA256: processed?.sha256, secondaryColor: secondary), status: .inLaundry))
        XCTAssertEqual(item.name, ItemDefaults.defaultName(color: StoredColor(red: 0.9, green: 0.1, blue: 0.1), subtype: .tee, category: .top))
        XCTAssertEqual(item.originalImage, original)
        XCTAssertEqual(item.processedImage, processed)
        XCTAssertEqual(item.secondaryColor, secondary)
        XCTAssertEqual(item.warmthLevels, [.mild])
        XCTAssertEqual(item.seasons, [], "seasons stay empty when not adjusted (audit M-04, kept as is)")
        XCTAssertNil(item.laundryEntryDate, "a new item never gets a laundry date, as in the App")
        XCTAssertEqual(item.createdAt, fixedNow)
        let stored = try await store.read { try $0.item(id: item.id) }
        XCTAssertEqual(stored, item)

        try await store.collectUnreferencedMedia(now: fixedNow.addingTimeInterval(ClosetStore.uploadGracePeriod * 2))
        XCTAssertEqual(store.media.storedHashes(), Set([original.sha256, processed!.sha256]), "saved images outlive the grace period")
    }

    func testCreationNeedsAnUploadedImage() async throws {
        let store = try makeStore()
        let service = ItemService(store: store, now: { fixedNow })
        await expectServiceError(.invalid("")) { _ = try await service.create(self.edit(images: nil)) }
        await expectServiceError(.invalid("")) {
            _ = try await service.create(self.edit(images: ImageChange(originalSHA256: String(repeating: "c", count: 64), processedSHA256: nil, secondaryColor: nil)))
        }
        let count = try await store.read { try $0.counts().items }
        XCTAssertEqual(count, 0)
    }

    func testReplacingImagesUpdatesColoursAndRemovesTheOldOnes() async throws {
        let store = try makeStore()
        let images = ImageService(store: store, processor: FakeImageProcessor(), now: { fixedNow })
        let service = ItemService(store: store, now: { fixedNow })
        let first = try await images.upload(SampleImages.jpeg(width: 100, height: 100)).ref
        let item = try await service.create(edit(images: ImageChange(originalSHA256: first.sha256, processedSHA256: nil, secondaryColor: nil), name: "旧图"))

        let unchanged = try await service.update(id: item.id, with: edit(images: nil, name: "改名"))
        XCTAssertEqual(unchanged.originalImage, first, "no image change keeps the images")

        let second = try await images.upload(SampleImages.jpeg(width: 200, height: 100)).ref
        let secondary = StoredColor(red: 0.2, green: 0.2, blue: 0.2)
        let updated = try await ItemService(store: store, now: { fixedNow.addingTimeInterval(ClosetStore.uploadGracePeriod * 2) }).update(
            id: item.id, with: edit(images: ImageChange(originalSHA256: second.sha256, processedSHA256: nil, secondaryColor: secondary), name: "新图"))
        XCTAssertEqual(updated.originalImage, second)
        XCTAssertEqual(updated.secondaryColor, secondary)
        XCTAssertEqual(store.media.storedHashes(), [second.sha256], "the replaced original is collected")
    }
}
