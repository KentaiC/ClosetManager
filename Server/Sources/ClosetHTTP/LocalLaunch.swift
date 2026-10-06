import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// 启动时查找前端构建产物。
public enum WebRootLocator {
    public enum LocateError: Error, CustomStringConvertible, Equatable {
        case missingIndex(String)

        public var description: String {
            switch self {
            case .missingIndex(let path): return "前端目录 \(path) 中没有 index.html，请先在 Web 目录运行 npm run build。"
            }
        }
    }

    /// 依次查找：`--web-root` 参数、环境变量 `CLOSET_WEB_ROOT`、当前目录下的 `Web/dist`。
    /// 显式指定的目录必须包含 index.html；自动查找找不到时返回 nil，服务只提供 API。
    public static func locate(explicit: String?, environment: [String: String], currentDirectory: URL) throws -> URL? {
        func hasIndex(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path)
        }
        for given in [explicit, environment["CLOSET_WEB_ROOT"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            let url = URL(fileURLWithPath: given, isDirectory: true, relativeTo: currentDirectory).standardizedFileURL
            guard hasIndex(url) else { throw LocateError.missingIndex(url.path) }
            return url
        }
        let fallback = currentDirectory.appendingPathComponent("Web/dist", isDirectory: true).standardizedFileURL
        return hasIndex(fallback) ? fallback : nil
    }
}

/// 选择监听端口。
public enum PortSelector {
    public static let defaultPort = 8765
    /// 默认端口被占用时，依次尝试之后的这么多个端口。
    public static let fallbackCount = 10

    public enum SelectError: Error, CustomStringConvertible, Equatable {
        case requestedPortInUse(Int)
        case noFreePort(ClosedRange<Int>)

        public var description: String {
            switch self {
            case .requestedPortInUse(let port): return "端口 \(port) 已被占用，请用 --port 指定其它端口。"
            case .noFreePort(let range): return "端口 \(range.lowerBound) 到 \(range.upperBound) 都已被占用，请用 --port 指定其它端口。"
            }
        }
    }

    /// 指定了端口时只用这个端口；没有指定时从默认端口开始找第一个空闲端口。
    public static func choose(requested: Int?, isAvailable: (Int) -> Bool) throws -> Int {
        if let requested {
            guard isAvailable(requested) else { throw SelectError.requestedPortInUse(requested) }
            return requested
        }
        let range = defaultPort...(defaultPort + fallbackCount - 1)
        guard let port = range.first(where: isAvailable) else { throw SelectError.noFreePort(range) }
        return port
    }

    /// 能否在 127.0.0.1 上绑定该端口。与服务端相同，允许复用处于 TIME_WAIT 的地址。
    public static func isAvailable(_ port: Int) -> Bool {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result == 0
    }
}

/// 服务启动后打开浏览器。用固定路径的系统命令和参数数组，不经过 shell。
public enum BrowserOpener {
    /// 当前平台打开网址的命令。没有已知命令的平台返回 nil。
    public static func command(for url: URL) -> (executable: URL, arguments: [String])? {
        #if os(macOS)
        return (URL(fileURLWithPath: "/usr/bin/open"), [url.absoluteString])
        #elseif os(Linux)
        let candidate = URL(fileURLWithPath: "/usr/bin/xdg-open")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return (candidate, [url.absoluteString])
        #else
        return nil
        #endif
    }

    /// 打开网址。失败时返回 false，由调用方提示用户手动打开。
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        guard let (executable, arguments) = command(for: url) else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
