import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

/// 图片上传、抠图取色、预览与相似单品检测。
struct ImageRoutes: Sendable {
    let images: ImageService
    let now: @Sendable () -> Date

    func register(on api: RouterGroup<BasicRequestContext>) {
        api.post("images", use: upload)
        api.post("images/:sha256/process", use: process)
        api.get("images/:sha256", use: preview)
        api.get("similar-items", use: similarItems)
    }

    /// 请求体是图片的原始字节。类型按文件头判断，忽略 Content-Type 与文件名。
    @Sendable func upload(_ request: Request, context: BasicRequestContext) async throws -> EditedResponse<APIUploadedImage> {
        let buffer: ByteBuffer
        do {
            buffer = try await request.body.collect(upTo: ImageService.maxUploadBytes)
        } catch let error as HTTPResponseError where error.status == .contentTooLarge {
            throw APIError(.contentTooLarge, code: "payload_too_large", message: "图片超过 \(ImageService.maxUploadBytes / 1024 / 1024) MB 上限。")
        }
        let uploaded = try await images.upload(Data(buffer.readableBytesView))
        return EditedResponse(status: .created, response: APIUploadedImage(uploaded.ref, width: uploaded.width, height: uploaded.height))
    }

    @Sendable func process(_ request: Request, context: BasicRequestContext) async throws -> APIProcessedImage {
        APIProcessedImage(try await images.process(sha256: context.parameters.get("sha256") ?? ""))
    }

    /// 预览已上传、可能尚未保存到单品的图片。只按哈希查已登记的图片，不接受路径。
    @Sendable func preview(_ request: Request, context: BasicRequestContext) async throws -> Response {
        let ref = try await images.media(sha256: context.parameters.get("sha256") ?? "")
        let kind: MediaVariantKind
        switch request.uri.queryParameters.get("variant") ?? "display" {
        case "display": kind = .display
        case "thumbnail": kind = .thumbnail
        case let other: throw APIError.invalidParameter("variant", String(other))
        }
        return try await ImageResponse.make(try await images.servable(ref, kind: kind), images: images, request: request, immutable: true)
    }

    @Sendable func similarItems(_ request: Request, context: BasicRequestContext) async throws -> APISimilarGroups {
        let timestamp = now()
        return APISimilarGroups(groups: try await images.similarGroups().map { $0.map { APIItem($0, now: timestamp) } })
    }
}

/// 图片响应：ETag、缓存策略、内容类型，以及无法识别的数据一律作为附件。
enum ImageResponse {
    static func make(_ ref: MediaRef, images: ImageService, request: Request, immutable: Bool) async throws -> Response {
        let etag = "\"\(ref.sha256)\""
        var headers: HTTPFields = [.eTag: etag]
        // 地址中带有内容哈希时可以长期缓存；内容变化后地址也会变化。
        headers[.cacheControl] = immutable ? "private, max-age=31536000, immutable" : "no-cache"
        if request.headers[.ifNoneMatch] == etag {
            return Response(status: .notModified, headers: headers)
        }
        let data = try images.data(of: ref)
        headers[.contentType] = ref.format.mimeType
        if ref.format == .unknown {
            // 无法识别的数据一律作为附件下载，绝不让浏览器按网页或脚本解释。
            headers[.contentDisposition] = "attachment; filename=\"\(ref.sha256).bin\""
        }
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}

/// 在请求处理期间告知响应模型服务端能否转换图片格式，用于计算 `displayable`。
struct ImageConversionMiddleware<Context: RequestContext>: RouterMiddleware {
    let available: Bool

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        try await APIImage.$conversionAvailable.withValue(available) { try await next(request, context) }
    }
}
