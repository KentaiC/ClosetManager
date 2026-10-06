import Foundation
import Crypto

/// 按内容哈希寻址的图片文件存储。
///
/// 文件路径完全由 SHA-256 决定：`<root>/<前两位>/<哈希>.<扩展名>`，不接受任何来自客户端的文件名或路径，
/// 因此不存在路径穿越；同一内容只存一份，写入是幂等的。
public struct MediaStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func url(for ref: MediaRef) -> URL {
        url(sha256: ref.sha256, fileExtension: ref.format.fileExtension)
    }

    private func url(sha256: String, fileExtension: String) -> URL {
        root.appendingPathComponent(String(sha256.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(sha256).\(fileExtension)")
    }

    /// 写入一份图片数据（已存在则跳过），返回其引用。
    @discardableResult
    public func write(_ data: Data) throws -> MediaRef {
        let ref = MediaRef(sha256: Self.sha256Hex(data), format: ImageFormat.detect(data), byteCount: data.count)
        let target = url(for: ref)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        return ref
    }

    public func read(_ ref: MediaRef) throws -> Data {
        let target = url(for: ref)
        guard FileManager.default.fileExists(atPath: target.path) else { throw StorageError.missingMedia(sha256: ref.sha256) }
        return try Data(contentsOf: target)
    }

    /// 磁盘上现有的全部文件哈希。
    public func storedHashes() -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var hashes = Set<String>()
        for case let file as URL in enumerator where file.pathExtension.isEmpty == false {
            let name = file.deletingPathExtension().lastPathComponent
            if name.count == 64 { hashes.insert(name) }
        }
        return hashes
    }

    /// 删除指定哈希对应的所有文件。
    public func remove(sha256: String) {
        let directory = root.appendingPathComponent(String(sha256.prefix(2)), isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.deletingPathExtension().lastPathComponent == sha256 {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
