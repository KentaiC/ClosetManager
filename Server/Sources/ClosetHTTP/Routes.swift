import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

/// 服务端版本号，随 API 一起返回。
public let closetServerVersion = "0.2.0"

/// `/api/v1` 下的路由。
struct APIRoutes: Sendable {
    let store: ClosetStore
    let catalog: CatalogService
    let capabilities: APIHealth.Capabilities

    func register(on router: Router<BasicRequestContext>) {
        let api = router.group("api/v1")
        api.get("health", use: health)
        api.get("meta") { _, _ in APIMeta.current }
        api.get("items", use: listItems)
        api.get("items/:id", use: getItem)
        api.get("items/:id/image", use: getItemImage)
        api.get("outfits", use: listOutfits)
        api.get("wear-records", use: listWearRecords)
        api.get("wear-records/active", use: activeWearRecord)
    }

    // MARK: - 处理函数

    @Sendable func health(_ request: Request, context: BasicRequestContext) async throws -> APIHealth {
        APIHealth(status: "ok", version: closetServerVersion, schemaVersion: try await store.schemaVersion(),
                  counts: try await catalog.counts(), capabilities: capabilities)
    }

    @Sendable func listItems(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIItem> {
        let query = request.uri.queryParameters
        let status: ItemStatus? = try Self.enumParameter(query.get("status"), name: "status")
        let category: ClosetCore.Category? = try Self.enumParameter(query.get("category"), name: "category")
        let items = try await catalog.items(ItemFilter(status: status, category: category))
        return APIList(items: items.map(APIItem.init))
    }

    @Sendable func getItem(_ request: Request, context: BasicRequestContext) async throws -> APIItem {
        let id = try Self.uuidParameter(context)
        guard let item = try await catalog.item(id: id) else { throw APIError.notFound("未找到该单品。") }
        return APIItem(item)
    }

    @Sendable func getItemImage(_ request: Request, context: BasicRequestContext) async throws -> Response {
        let id = try Self.uuidParameter(context)
        guard let item = try await catalog.item(id: id) else { throw APIError.notFound("未找到该单品。") }
        let variant = request.uri.queryParameters.get("variant") ?? "display"
        let ref: MediaRef?
        switch variant {
        case "display": ref = item.displayImage
        case "processed": ref = item.processedImage
        case "original": ref = item.originalImage
        default: throw APIError.invalidParameter("variant", variant)
        }
        guard let ref else { throw APIError.notFound("该单品没有这张图片。") }

        let etag = "\"\(ref.sha256)\""
        var headers: HTTPFields = [.eTag: etag]
        // URL 中带有内容哈希时可以长期缓存；内容变化后 URL 也会变化。
        if let version = request.uri.queryParameters.get("v"), ref.sha256.hasPrefix(version), !version.isEmpty {
            headers[.cacheControl] = "private, max-age=31536000, immutable"
        } else {
            headers[.cacheControl] = "no-cache"
        }
        if request.headers[.ifNoneMatch] == etag {
            return Response(status: .notModified, headers: headers)
        }
        let data = try store.media.read(ref)
        headers[.contentType] = ref.format.mimeType
        if ref.format == .unknown {
            // 无法识别的数据一律作为附件下载，绝不让浏览器按网页或脚本解释。
            headers[.contentDisposition] = "attachment; filename=\"\(ref.sha256).bin\""
        }
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func listOutfits(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIOutfit> {
        let favorite = request.uri.queryParameters.get("favorite")
        guard favorite == nil || favorite == "true" || favorite == "false" else {
            throw APIError.invalidParameter("favorite", favorite ?? "")
        }
        let outfits = try await catalog.outfits(favoritesOnly: favorite == "true")
        return APIList(items: outfits.map(APIOutfit.init))
    }

    @Sendable func listWearRecords(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIWearRecord> {
        APIList(items: try await catalog.wearRecords().map(APIWearRecord.init))
    }

    @Sendable func activeWearRecord(_ request: Request, context: BasicRequestContext) async throws -> APIActiveWearRecord {
        APIActiveWearRecord(record: try await catalog.wearRecords(activeOnly: true).first.map(APIWearRecord.init))
    }

    // MARK: - 参数解析

    static func uuidParameter(_ context: BasicRequestContext, name: String = "id") throws -> UUID {
        let raw = context.parameters.get(name) ?? ""
        guard let id = UUID(uuidString: raw) else { throw APIError.invalidParameter(name, raw) }
        return id
    }

    static func enumParameter<E: RawRepresentable>(_ raw: String?, name: String) throws -> E? where E.RawValue == String {
        guard let raw, !raw.isEmpty else { return nil }
        guard let value = E(rawValue: raw) else { throw APIError.invalidParameter(name, raw) }
        return value
    }
}
