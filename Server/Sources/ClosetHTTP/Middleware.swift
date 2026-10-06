import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// 本机访问策略：只接受回环地址的 Host 与同源请求。
public struct LoopbackPolicy: Sendable {
    /// 允许的主机名（不含端口，小写）。
    public var allowedHosts: Set<String>
    /// 服务监听的端口，用于校验 Origin。
    public var port: Int

    public init(port: Int, allowedHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]) {
        self.port = port
        self.allowedHosts = allowedHosts
    }

    /// 从 Host 或 authority 中取出主机名（去掉端口与 IPv6 方括号，转小写）。
    public static func hostname(fromAuthority authority: String) -> String {
        let lower = authority.lowercased()
        if lower.hasPrefix("[") {
            guard let end = lower.firstIndex(of: "]") else { return lower }
            return String(lower[lower.index(after: lower.startIndex)..<end])
        }
        let parts = lower.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[0]) : lower
    }

    /// Host 是否指向本机。用于防御 DNS rebinding：攻击者域名即使解析到 127.0.0.1，Host 仍是攻击者域名。
    public func isAllowedAuthority(_ authority: String?) -> Bool {
        guard let authority, !authority.isEmpty else { return false }
        return allowedHosts.contains(Self.hostname(fromAuthority: authority))
    }

    /// Origin 是否为本服务自身。
    public func isAllowedOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), url.scheme == "http", let host = url.host?.lowercased() else { return false }
        let bareHost = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host
        return allowedHosts.contains(bareHost) && url.port == port
    }
}

/// 拒绝 Host 不是本机的请求。
public struct HostGuardMiddleware<Context: RequestContext>: RouterMiddleware {
    let policy: LoopbackPolicy

    public init(policy: LoopbackPolicy) {
        self.policy = policy
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard policy.isAllowedAuthority(request.head.authority) else {
            throw APIError(.forbidden, code: "host_not_allowed", message: "只允许通过本机地址访问。")
        }
        return try await next(request, context)
    }
}

/// 写请求的跨站防护。
///
/// 会改变数据的请求必须带 `X-Closet-Client` 头。跨源网页要附加自定义头必须先通过 CORS 预检，
/// 而本服务不应答任何跨源预检，所以其它网站无法伪造这类请求。若请求带有 Origin 或
/// Sec-Fetch-Site，还要求它们表明请求来自本服务自身。
public struct RequestGuardMiddleware<Context: RequestContext>: RouterMiddleware {
    public static var clientHeader: HTTPField.Name { HTTPField.Name("X-Closet-Client")! }
    let policy: LoopbackPolicy

    public init(policy: LoopbackPolicy) {
        self.policy = policy
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let safe: Set<HTTPRequest.Method> = [.get, .head]
        if !safe.contains(request.method) {
            let rejected = APIError(.forbidden, code: "request_rejected", message: "请求来源未通过校验。")
            guard request.headers[Self.clientHeader] != nil else { throw rejected }
            if let origin = request.headers[HTTPField.Name("Origin")!], !policy.isAllowedOrigin(origin) { throw rejected }
            if let site = request.headers[HTTPField.Name("Sec-Fetch-Site")!], !["same-origin", "none"].contains(site) { throw rejected }
        }
        return try await next(request, context)
    }
}

/// 把抛出的错误统一转换为 JSON 错误响应；未知错误只记录日志，不向客户端暴露细节。
public struct APIErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as APIError {
            return APIError.jsonResponse(status: error.status, code: error.code, message: error.message)
        } catch let error as HTTPResponseError {
            let (code, message) = Self.describe(error.status)
            return APIError.jsonResponse(status: error.status, code: code, message: message)
        } catch {
            context.logger.error("Unhandled error: \(String(describing: error))")
            return APIError.jsonResponse(status: .internalServerError, code: "internal_error", message: "服务器内部错误。")
        }
    }

    static func describe(_ status: HTTPResponse.Status) -> (String, String) {
        switch status {
        case .notFound: return ("not_found", "未找到请求的资源。")
        case .methodNotAllowed: return ("method_not_allowed", "不支持该请求方法。")
        case .contentTooLarge: return ("payload_too_large", "请求内容过大。")
        case .badRequest: return ("bad_request", "请求格式不正确。")
        case .unsupportedMediaType: return ("unsupported_media_type", "不支持的内容类型。")
        default: return ("http_\(status.code)", "请求失败。")
        }
    }
}

/// 为所有响应附加安全相关的头。
public struct SecurityHeadersMiddleware<Context: RequestContext>: RouterMiddleware {
    /// 只允许加载本服务自身的资源；图片额外允许 blob 与 data，用于前端本地预览。
    public static var contentSecurityPolicy: String {
        "default-src 'self'; img-src 'self' blob: data:; style-src 'self'; script-src 'self'; connect-src 'self'; "
            + "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
    }

    public init() {}

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        response.headers[.contentSecurityPolicy] = Self.contentSecurityPolicy
        response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
        response.headers[HTTPField.Name("X-Frame-Options")!] = "DENY"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        response.headers[HTTPField.Name("Cross-Origin-Opener-Policy")!] = "same-origin"
        response.headers[HTTPField.Name("Cross-Origin-Resource-Policy")!] = "same-origin"
        let path = request.uri.path
        if path.hasPrefix("/api/") {
            if response.headers[.cacheControl] == nil { response.headers[.cacheControl] = "no-store" }
        } else if path.hasPrefix("/assets/"), response.status == .ok {
            // 前端构建产物的文件名含内容哈希，可以长期缓存。
            response.headers[.cacheControl] = "public, max-age=31536000, immutable"
        } else if response.headers[.cacheControl] == nil {
            response.headers[.cacheControl] = "no-cache"
        }
        return response
    }
}
