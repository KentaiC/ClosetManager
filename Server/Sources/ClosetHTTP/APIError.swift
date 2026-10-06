import Foundation
import Hummingbird

/// API 错误：统一以 `{"error":{"code":"…","message":"…"}}` 返回。
public struct APIError: HTTPResponseError, Sendable {
    public let status: HTTPResponse.Status
    public let code: String
    public let message: String

    public init(_ status: HTTPResponse.Status, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    public static func notFound(_ message: String = "未找到请求的资源。") -> APIError {
        APIError(.notFound, code: "not_found", message: message)
    }

    public static func invalidParameter(_ name: String, _ value: String) -> APIError {
        APIError(.badRequest, code: "invalid_parameter", message: "参数 \(name) 的值「\(value)」无效。")
    }

    public func response(from request: Request, context: some RequestContext) throws -> Response {
        Self.jsonResponse(status: status, code: code, message: message)
    }

    struct Body: Encodable {
        struct Detail: Encodable {
            let code: String
            let message: String
        }
        let error: Detail
    }

    static func jsonResponse(status: HTTPResponse.Status, code: String, message: String) -> Response {
        let data = (try? JSONEncoder().encode(Body(error: .init(code: code, message: message)))) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
