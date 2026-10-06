import XCTest
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ClosetHTTP

final class LocalLaunchTests: XCTestCase {
    private func directory(withIndex: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("webroot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if withIndex { try Data("<!doctype html>".utf8).write(to: url.appendingPathComponent("index.html")) }
        return url
    }

    func testWebRootSearchOrder() throws {
        let explicit = try directory(withIndex: true)
        let fromEnvironment = try directory(withIndex: true)
        let repository = try directory(withIndex: false)
        let dist = repository.appendingPathComponent("Web/dist", isDirectory: true)
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)

        XCTAssertNil(try WebRootLocator.locate(explicit: nil, environment: [:], currentDirectory: repository), "no build yet: API only")
        try Data("<!doctype html>".utf8).write(to: dist.appendingPathComponent("index.html"))
        XCTAssertEqual(try WebRootLocator.locate(explicit: nil, environment: [:], currentDirectory: repository)?.path, dist.standardizedFileURL.path)
        XCTAssertEqual(try WebRootLocator.locate(explicit: nil, environment: ["CLOSET_WEB_ROOT": fromEnvironment.path], currentDirectory: repository)?.path,
                       fromEnvironment.standardizedFileURL.path)
        XCTAssertEqual(try WebRootLocator.locate(explicit: explicit.path, environment: ["CLOSET_WEB_ROOT": fromEnvironment.path], currentDirectory: repository)?.path,
                       explicit.standardizedFileURL.path)
        XCTAssertEqual(try WebRootLocator.locate(explicit: "Web/dist", environment: [:], currentDirectory: repository)?.path, dist.standardizedFileURL.path,
                       "relative paths resolve against the current directory")
    }

    func testAnExplicitWebRootMustContainTheBuild() throws {
        let empty = try directory(withIndex: false)
        XCTAssertThrowsError(try WebRootLocator.locate(explicit: empty.path, environment: [:], currentDirectory: empty)) { error in
            XCTAssertEqual(error as? WebRootLocator.LocateError, .missingIndex(empty.standardizedFileURL.path))
        }
        XCTAssertThrowsError(try WebRootLocator.locate(explicit: nil, environment: ["CLOSET_WEB_ROOT": empty.path], currentDirectory: empty))
    }

    func testPortChoice() throws {
        XCTAssertEqual(try PortSelector.choose(requested: nil) { _ in true }, 8765)
        XCTAssertEqual(try PortSelector.choose(requested: nil) { $0 > 8767 }, 8768)
        XCTAssertThrowsError(try PortSelector.choose(requested: nil) { _ in false }) { error in
            XCTAssertEqual(error as? PortSelector.SelectError, .noFreePort(8765...8774))
        }
        XCTAssertEqual(try PortSelector.choose(requested: 9000) { _ in true }, 9000)
        XCTAssertThrowsError(try PortSelector.choose(requested: 9000) { $0 != 9000 }) { error in
            XCTAssertEqual(error as? PortSelector.SelectError, .requestedPortInUse(9000), "an explicit port is never swapped")
        }
    }

    func testDetectsAPortThatIsAlreadyListening() throws {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        XCTAssertGreaterThanOrEqual(fd, 0)
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        XCTAssertTrue(bound)
        let port = Int(UInt16(bigEndian: address.sin_port))
        XCTAssertFalse(PortSelector.isAvailable(port))
        close(fd)
        XCTAssertTrue(PortSelector.isAvailable(port))
    }

    func testBrowserCommandUsesAFixedExecutableAndPassesTheURLAsOneArgument() throws {
        let url = URL(string: "http://127.0.0.1:8765/")!
        guard let command = BrowserOpener.command(for: url) else {
            #if os(macOS)
            XCTFail("macOS always has /usr/bin/open")
            #endif
            return
        }
        XCTAssertTrue(command.executable.path.hasPrefix("/usr/bin/"))
        XCTAssertEqual(command.arguments, ["http://127.0.0.1:8765/"])
    }
}
