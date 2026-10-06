import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

/// 备份的导出与导入。两者都要求写请求的来源校验：导出包含全部数据，只允许本服务自己的页面发起。
struct BackupRoutes: Sendable {
    /// 导入文件的大小上限。备份内联全部图片，与 App 相同整份读入内存解析。
    static let maxImportBytes = 1024 * 1024 * 1024

    let store: ClosetStore
    let now: @Sendable () -> Date

    func register(on api: RouterGroup<BasicRequestContext>) {
        api.post("backup/export", use: export)
        api.post("backup/import", use: restore)
    }

    @Sendable func export(_ request: Request, context: BasicRequestContext) async throws -> Response {
        let data = try await BackupExporter(store: store).export()
        return Response(
            status: .ok,
            headers: [
                .contentType: "application/octet-stream",
                .contentDisposition: "attachment; filename=\"\(BackupExporter.fileName(at: now()))\"",
            ],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    /// 请求体是 `.wardrobe` 文件的原始字节。`apply=true` 时才写入，否则只预检。
    @Sendable func restore(_ request: Request, context: BasicRequestContext) async throws -> APIImportReport {
        let query = request.uri.queryParameters
        let mode: RestoreMode = try parse(query.get("mode") ?? "merge", "mode")
        let apply: Bool
        switch query.get("apply") ?? "false" {
        case "true": apply = true
        case "false": apply = false
        case let other: throw APIError.invalidParameter("apply", String(other))
        }
        let buffer: ByteBuffer
        do {
            buffer = try await request.body.collect(upTo: Self.maxImportBytes)
        } catch let error as HTTPResponseError where error.status == .contentTooLarge {
            throw APIError(.contentTooLarge, code: "payload_too_large", message: "备份文件超过 1 GB 上限。")
        }
        do {
            return APIImportReport(report: try await BackupRestoreService(store: store, now: now)
                .restore(Data(buffer.readableBytesView), mode: mode, apply: apply))
        } catch ImportError.unreadable {
            throw APIError(.badRequest, code: "invalid_backup", message: "无法读取备份文件，请确认它是 App 导出的 .wardrobe 文件。")
        }
    }
}

/// 导入报告，字段与 `closet-server import --json` 的输出相同。
struct APIImportReport: Encodable, ResponseEncodable {
    let report: ImportReport

    func encode(to encoder: Encoder) throws {
        try report.encode(to: encoder)
    }
}
