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
    let images: ImageService
    let now: @Sendable () -> Date

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
        WriteRoutes(store: store, catalog: catalog, now: now).register(on: api)
        ImageRoutes(images: images, now: now).register(on: api)
    }

    // MARK: - 处理函数

    @Sendable func health(_ request: Request, context: BasicRequestContext) async throws -> APIHealth {
        APIHealth(status: "ok", version: closetServerVersion, schemaVersion: try await store.schemaVersion(),
                  counts: try await catalog.counts(), capabilities: images.capabilities)
    }

    @Sendable func listItems(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIItem> {
        let query = request.uri.queryParameters
        let status: ItemStatus? = try Self.enumParameter(query.get("status"), name: "status")
        let category: ClosetCore.Category? = try Self.enumParameter(query.get("category"), name: "category")
        let sort: ItemFilter.Sort = try Self.enumParameter(query.get("sort"), name: "sort") ?? .createdAt
        let items = try await catalog.items(ItemFilter(status: status, category: category, sort: sort))
        let timestamp = now()
        return APIList(items: items.map { APIItem($0, now: timestamp) })
    }

    @Sendable func getItem(_ request: Request, context: BasicRequestContext) async throws -> APIItem {
        let id = try Self.uuidParameter(context)
        guard let item = try await catalog.item(id: id) else { throw APIError.notFound("未找到该单品。") }
        return APIItem(item, now: now())
    }

    @Sendable func getItemImage(_ request: Request, context: BasicRequestContext) async throws -> Response {
        let id = try Self.uuidParameter(context)
        guard let item = try await catalog.item(id: id) else { throw APIError.notFound("未找到该单品。") }
        let variant = request.uri.queryParameters.get("variant") ?? "display"
        let ref: MediaRef?
        let kind: MediaVariantKind?
        switch variant {
        case "display": (ref, kind) = (item.displayImage, .display)
        case "thumbnail": (ref, kind) = (item.displayImage, .thumbnail)
        case "processed": (ref, kind) = (item.processedImage, nil)
        case "original": (ref, kind) = (item.originalImage, nil)
        default: throw APIError.invalidParameter("variant", variant)
        }
        guard let ref else { throw APIError.notFound("该单品没有这张图片。") }
        // 展示图与缩略图在需要时换成派生图；原图与抠图结果按存储的字节返回。
        var served = ref
        if let kind { served = try await images.servable(ref, kind: kind) }
        let version = request.uri.queryParameters.get("v") ?? ""
        return try await ImageResponse.make(served, images: images, request: request, immutable: !version.isEmpty && ref.sha256.hasPrefix(version))
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
