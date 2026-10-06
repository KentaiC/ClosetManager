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
public func makeRouter(
    store: ClosetStore,
    configuration: ServerConfiguration,
    policy: LoopbackPolicy? = nil,
    capabilities: APIHealth.Capabilities = .init(backgroundRemoval: false, similarityDetection: false)
) -> Router<BasicRequestContext> {
    let policy = policy ?? LoopbackPolicy(port: configuration.port)
    let router = Router(context: BasicRequestContext.self)
    router.addMiddleware {
        SecurityHeadersMiddleware()
        APIErrorMiddleware()
        HostGuardMiddleware(policy: policy)
        RequestGuardMiddleware(policy: policy)
    }
    APIRoutes(store: store, catalog: CatalogService(store: store), capabilities: capabilities).register(on: router)
    return router
}

/// 构建可运行的服务端应用。
public func makeApplication(
    store: ClosetStore,
    configuration: ServerConfiguration,
    logger: Logger = Logger(label: "closet-server")
) -> some ApplicationProtocol {
    Application(
        router: makeRouter(store: store, configuration: configuration),
        configuration: .init(address: .hostname(ServerConfiguration.host, port: configuration.port), serverName: "ClosetManager"),
        logger: logger
    )
}
