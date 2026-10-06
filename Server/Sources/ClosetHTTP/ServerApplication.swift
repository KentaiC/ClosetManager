import Foundation
import ClosetStorage
import ClosetServices
import Hummingbird
import Logging

/// 服务端运行配置。
public struct ServerConfiguration: Sendable {
    /// 只监听本机回环地址（决策 D2）。
    public static let host = "127.0.0.1"
    public var port: Int
    /// 前端构建产物目录；为 nil 时只提供 API。
    public var webRoot: URL?

    public init(port: Int = 8765, webRoot: URL? = nil) {
        self.port = port
        self.webRoot = webRoot
    }
}

/// 组装路由与中间件。
///
/// 中间件由外到内：安全响应头、错误转 JSON、Host 校验、写请求来源校验。
/// 它们作用于所有请求，包括未匹配到路由的请求。
///
/// - Parameter processor: 图片处理的平台实现。默认不做处理，正式运行时由 `makeApplication` 传入当前平台的实现。
public func makeRouter(
    store: ClosetStore,
    configuration: ServerConfiguration,
    policy: LoopbackPolicy? = nil,
    processor: any ImageProcessor = UnavailableImageProcessor(),
    now: @escaping @Sendable () -> Date = Date.init
) -> Router<BasicRequestContext> {
    let policy = policy ?? LoopbackPolicy(port: configuration.port)
    let router = Router(context: BasicRequestContext.self)
    router.addMiddleware {
        SecurityHeadersMiddleware()
        APIErrorMiddleware()
        HostGuardMiddleware(policy: policy)
        RequestGuardMiddleware(policy: policy)
        ImageConversionMiddleware(available: processor.capabilities.formatConversion)
    }
    if let webRoot = configuration.webRoot {
        // 静态文件在安全中间件之内处理，同样经过 Host 校验并附加安全响应头。
        router.add(middleware: FileMiddleware(webRoot.path, searchForIndexHtml: true))
    }
    let images = ImageService(store: store, processor: processor, now: now)
    APIRoutes(store: store, catalog: CatalogService(store: store), images: images, now: now).register(on: router)
    if let webRoot = configuration.webRoot {
        registerSinglePageFallback(on: router, webRoot: webRoot)
    }
    return router
}

/// 前端路由的深链接（如 /laundry、/items/<id>）回退到 index.html，由前端决定显示哪个页面。
/// API 路径与带扩展名的文件路径不回退，缺失时如实返回 404。
func registerSinglePageFallback(on router: Router<BasicRequestContext>, webRoot: URL) {
    let index = webRoot.appendingPathComponent("index.html")
    router.get("**") { request, _ -> Response in
        let path = request.uri.path
        let lastComponent = path.split(separator: "/").last ?? ""
        guard !path.hasPrefix("/api/"), !lastComponent.contains(".") else {
            throw APIError.notFound()
        }
        guard let html = try? Data(contentsOf: index) else {
            throw APIError(.notFound, code: "web_ui_missing", message: "未找到前端页面，请先构建 Web 目录。")
        }
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: html)))
    }
}

/// 构建可运行的服务端应用。
///
/// - Parameter onServerRunning: 开始监听后调用，用于打印地址或打开浏览器。
public func makeApplication(
    store: ClosetStore,
    configuration: ServerConfiguration,
    processor: any ImageProcessor = ImageProcessors.platformDefault,
    logger: Logger = Logger(label: "closet-server"),
    onServerRunning: @escaping @Sendable () async -> Void = {}
) -> some ApplicationProtocol {
    Application(
        router: makeRouter(store: store, configuration: configuration, processor: processor),
        configuration: .init(address: .hostname(ServerConfiguration.host, port: configuration.port), serverName: "ClosetManager"),
        onServerRunning: { _ in await onServerRunning() },
        logger: logger
    )
}
