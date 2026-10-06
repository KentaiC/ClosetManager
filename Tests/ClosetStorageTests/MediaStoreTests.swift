import XCTest
@testable import ClosetStorage

final class MediaStoreTests: XCTestCase {
    func testWriteIsContentAddressedAndIdempotent() throws {
        let media = MediaStore(root: try makeTemporaryDirectory())
        let a = try media.write(pngBytes)
        let b = try media.write(pngBytes)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.sha256.count, 64)
        XCTAssertTrue(a.sha256.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(media.url(for: a).lastPathComponent, "\(a.sha256).png")
        XCTAssertEqual(media.url(for: a).deletingLastPathComponent().lastPathComponent, String(a.sha256.prefix(2)))
        XCTAssertEqual(try media.read(a), pngBytes)
        XCTAssertEqual(media.storedHashes(), [a.sha256])
    }

    func testKnownDigest() {
        XCTAssertEqual(MediaStore.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMissingMediaThrows() throws {
        let media = MediaStore(root: try makeTemporaryDirectory())
        let ref = MediaRef(sha256: String(repeating: "a", count: 64), format: .png, byteCount: 1)
        XCTAssertThrowsError(try media.read(ref)) { XCTAssertEqual($0 as? StorageError, .missingMedia(sha256: ref.sha256)) }
    }

    func testFormatDetection() {
        XCTAssertEqual(ImageFormat.detect(pngBytes), .png)
        XCTAssertEqual(ImageFormat.detect(jpegBytes), .jpeg)
        XCTAssertEqual(ImageFormat.detect(Data("GIF89a....".utf8)), .gif)
        XCTAssertEqual(ImageFormat.detect(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)), .webp)
        XCTAssertEqual(ImageFormat.detect(Data([0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0])), .heic)
        XCTAssertEqual(ImageFormat.detect(Data([0, 0, 0, 0x18] + Array("ftypmif1".utf8) + [0, 0, 0, 0])), .heif)
        XCTAssertEqual(ImageFormat.detect(Data([0, 0, 0, 0x18] + Array("ftypavif".utf8) + [0, 0, 0, 0])), .avif)
        XCTAssertEqual(ImageFormat.detect(Data([0x49, 0x49, 0x2A, 0x00, 1])), .tiff)
        XCTAssertEqual(ImageFormat.detect(Data("BM....".utf8)), .bmp)
        XCTAssertEqual(ImageFormat.detect(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script/></svg>".utf8)), .unknown)
        XCTAssertEqual(ImageFormat.detect(Data()), .unknown)
        XCTAssertFalse(ImageFormat.heic.isBrowserDisplayable)
        XCTAssertTrue(ImageFormat.png.isBrowserDisplayable)
        XCTAssertEqual(ImageFormat.unknown.mimeType, "application/octet-stream")
    }

    func testGarbageCollectionRemovesUnreferencedRowsAndFiles() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let kept = try store.media.write(pngBytes)
        let orphanRow = try store.media.write(jpegBytes)
        let strayFile = try store.media.write(Data("stray".utf8))
        let item = makeItem(processed: kept)
        try await store.transaction { s in try s.insertItem(item); try s.insertMedia(orphanRow) }
        let removed = try await store.collectUnreferencedMedia()
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(store.media.storedHashes(), [kept.sha256])
        let counts = try await store.read { try $0.counts() }
        XCTAssertEqual(counts.media, 1)
        _ = strayFile
    }
}

final class UploadAndVariantTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentUploadsSurviveCollectionUntilTheGracePeriodEnds() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let upload = try store.media.write(pngBytes)
        try await store.transaction { try $0.recordUpload(upload, at: Date(timeIntervalSince1970: 1_800_000_000)) }

        let removedInGrace = try await store.collectUnreferencedMedia(now: now.addingTimeInterval(ClosetStore.uploadGracePeriod - 1))
        XCTAssertEqual(removedInGrace, 0)
        XCTAssertEqual(store.media.storedHashes(), [upload.sha256])
        let stillRegistered = try await store.read { try $0.media(sha256: upload.sha256) }
        XCTAssertNotNil(stillRegistered)

        let removedAfterGrace = try await store.collectUnreferencedMedia(now: now.addingTimeInterval(ClosetStore.uploadGracePeriod + 1))
        XCTAssertEqual(removedAfterGrace, 1)
        XCTAssertTrue(store.media.storedHashes().isEmpty)
        let registeredAfterGrace = try await store.read { try $0.media(sha256: upload.sha256) }
        XCTAssertNil(registeredAfterGrace)
    }

    func testAnUploadSavedToAnItemOutlivesItsUploadRecord() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let upload = try store.media.write(pngBytes)
        try await store.transaction { session in
            try session.recordUpload(upload, at: Date(timeIntervalSince1970: 1_800_000_000))
            try session.insertItem(makeItem(original: upload))
        }
        try await store.collectUnreferencedMedia(now: now.addingTimeInterval(ClosetStore.uploadGracePeriod * 3))
        XCTAssertEqual(store.media.storedHashes(), [upload.sha256])
    }

    func testDeletedItemMediaIsStillCollectedImmediately() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let ref = try store.media.write(pngBytes)
        let item = makeItem(processed: ref)
        try await store.transaction { try $0.insertItem(item) }
        try await store.transaction { _ = try $0.deleteItem(id: item.id) }
        let removed = try await store.collectUnreferencedMedia(now: now)
        XCTAssertEqual(removed, 1)
    }

    func testVariantsLiveAndDieWithTheirSource() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let source = try store.media.write(pngBytes)
        let thumbnail = try store.media.write(jpegBytes)
        let item = makeItem(original: source)
        try await store.transaction { session in
            try session.insertItem(item)
            try session.insertVariant(of: source.sha256, kind: .thumbnail, variant: thumbnail)
        }
        let cached = try await store.read { try $0.variant(of: source.sha256, kind: .thumbnail) }
        XCTAssertEqual(cached, thumbnail)
        let missingDisplay = try await store.read { try $0.variant(of: source.sha256, kind: .display) }
        XCTAssertNil(missingDisplay)

        let removedWhileReferenced = try await store.collectUnreferencedMedia(now: now)
        XCTAssertEqual(removedWhileReferenced, 0, "a variant of a referenced image is referenced")
        try await store.transaction { _ = try $0.deleteItem(id: item.id) }
        let removedAfterDelete = try await store.collectUnreferencedMedia(now: now)
        XCTAssertEqual(removedAfterDelete, 2)
        let variantAfterDelete = try await store.read { try $0.variant(of: source.sha256, kind: .thumbnail) }
        XCTAssertNil(variantAfterDelete)
        let mediaRows = try await store.read { try $0.counts() }.media
        XCTAssertEqual(mediaRows, 0)
    }

    func testVariantKindIsConstrained() async throws {
        let store = try ClosetStore(inMemoryWithMediaRoot: try makeTemporaryDirectory())
        let ref = try store.media.write(pngBytes)
        try await store.transaction { try $0.insertMedia(ref) }
        let rejected = expectation(description: "unknown kind rejected")
        do {
            try await store.transaction { session in
                try session.db.execute("INSERT INTO media_variants (source_sha256, kind, sha256, created_at) VALUES ('\(ref.sha256)', 'poster', '\(ref.sha256)', 0);")
            }
        } catch { rejected.fulfill() }
        await fulfillment(of: [rejected], timeout: 1)
    }
}
