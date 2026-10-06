import ArgumentParser
import ClosetCore
import ClosetHTTP
import ClosetServices
import ClosetStorage
import Foundation
import Hummingbird
import Logging

@main
struct ClosetServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "closet-server",
        abstract: "Closet Manager 本地 Web 服务。",
        version: closetServerVersion,
        subcommands: [Serve.self, Import.self],
        defaultSubcommand: Serve.self
    )
}

struct DataDirectoryOption: ParsableArguments {
    @Option(name: .customLong("data-dir"), help: "数据目录。默认在用户的应用数据目录下的 ClosetManager。")
    var path: String?

    var directory: DataDirectory {
        DataDirectory(root: path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? DataDirectory.defaultRoot())
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "启动本地服务，只监听 127.0.0.1。")

    @OptionGroup var data: DataDirectoryOption

    @Option(help: "监听端口。不指定时使用 8765，被占用则依次尝试 8766 到 8774。")
    var port: Int?

    @Option(name: .customLong("web-root"), help: "前端构建产物目录。不指定时依次查找环境变量 CLOSET_WEB_ROOT 与当前目录下的 Web/dist。")
    var webRoot: String?

    @Flag(help: "服务启动后在默认浏览器中打开。")
    var open = false

    func validate() throws {
        if let port, !(1...65535).contains(port) { throw ValidationError("--port 必须在 1 到 65535 之间。") }
    }

    func run() async throws {
        var logger = Logger(label: "closet-server")
        logger.logLevel = .info
        let directory = data.directory
        let web: URL?
        let chosenPort: Int
        do {
            web = try WebRootLocator.locate(
                explicit: webRoot, environment: ProcessInfo.processInfo.environment,
                currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
            chosenPort = try PortSelector.choose(requested: port, isAvailable: PortSelector.isAvailable)
        } catch let error as CustomStringConvertible & Error {
            Console.error(error.description)
            throw ExitCode(1)
        }
        let store = try ClosetStore(directory: directory)
        let removed = try await store.collectUnreferencedMedia()
        logger.info("Data directory: \(directory.root.path)")
        if removed > 0 { logger.info("Removed \(removed) unreferenced media files") }
        if web == nil { logger.warning("Web UI not found; serving the API only. Build it with: cd Web && npm ci && npm run build") }
        let processor = ImageProcessors.platformDefault
        if !processor.capabilities.backgroundRemoval {
            logger.info("Image processing is unavailable on this platform: uploads are stored, but background removal, colour extraction, format conversion and similarity detection need macOS")
        }
        let configuration = ServerConfiguration(port: chosenPort, webRoot: web)
        let address = URL(string: "http://\(ServerConfiguration.host):\(chosenPort)/")!
        let shouldOpen = open
        let app = makeApplication(store: store, configuration: configuration, processor: processor, logger: logger) {
            Console.say("Closet Manager 已启动：\(address.absoluteString)")
            if chosenPort != PortSelector.defaultPort, port == nil {
                Console.say("默认端口 \(PortSelector.defaultPort) 已被占用，改用 \(chosenPort)。浏览器中的界面偏好按端口分别保存。")
            }
            Console.say("按 Ctrl-C 停止。")
            if shouldOpen, web != nil, !BrowserOpener.open(address) {
                Console.say("无法自动打开浏览器，请手动访问上面的地址。")
            }
        }
        try await app.runService()
    }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "导入 App 导出的 .wardrobe 备份。默认只做预检，加 --apply 才写入；写入前自动备份当前数据。")

    @OptionGroup var data: DataDirectoryOption

    @Argument(help: ".wardrobe 文件路径。")
    var file: String

    @Option(help: "导入方式：merge（合并，按 id 跳过已有记录）或 overwrite（清空后导入）。")
    var mode = "merge"

    @Flag(help: "实际写入数据。不加此项时只输出预检报告。")
    var apply = false

    @Flag(help: "以 JSON 输出报告。")
    var json = false

    func validate() throws {
        guard RestoreMode(rawValue: mode) != nil else {
            throw ValidationError("--mode 只能是 merge 或 overwrite。")
        }
    }

    func run() async throws {
        let restoreMode = RestoreMode(rawValue: mode)!
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        let store = try ClosetStore(directory: self.data.directory)
        let report = try await BackupRestoreService(store: store).restore(data, mode: restoreMode, apply: apply)
        print(try render(report))
        if !report.errors.isEmpty { throw ExitCode(2) }
    }

    func render(_ report: ImportReport) throws -> String {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }
        var lines = [
            report.applied ? "导入完成。" : (report.errors.isEmpty ? "预检通过，未写入数据。加 --apply 执行导入。" : "预检发现错误，未写入数据。"),
            "模式：\(report.mode.rawValue)，备份版本：\(report.backupVersion)",
            "单品：备份 \(report.items.inBackup)，导入 \(report.items.toImport)，跳过 \(report.items.skippedExisting)",
            "穿搭：备份 \(report.outfits.inBackup)，导入 \(report.outfits.toImport)，跳过 \(report.outfits.skippedExisting)",
            "穿着记录：备份 \(report.wearRecords.inBackup)，导入 \(report.wearRecords.toImport)，跳过 \(report.wearRecords.skippedExisting)",
            "图片：\(report.imageCount) 张，共 \(report.imageBytes) 字节",
        ]
        if let snapshot = report.preImportBackup { lines.append("导入前的数据已备份为 backups/before-import/\(snapshot)") }
        for issue in report.errors { lines.append("错误 [\(issue.code.rawValue)] \(issue.entity ?? "") \(issue.id ?? "")：\(issue.message)") }
        for issue in report.warnings { lines.append("警告 [\(issue.code.rawValue)] \(issue.entity ?? "") \(issue.id ?? "")：\(issue.message)") }
        return lines.joined(separator: "\n")
    }
}

/// 面向使用者的提示。直接写入文件描述符，输出被重定向时也会立即出现。
enum Console {
    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func error(_ line: String) {
        FileHandle.standardError.write(Data(("错误：" + line + "\n").utf8))
    }
}
