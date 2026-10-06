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

    @Option(help: "监听端口。")
    var port = 8765

    @Option(name: .customLong("web-root"), help: "前端构建产物目录。")
    var webRoot: String?

    func run() async throws {
        var logger = Logger(label: "closet-server")
        logger.logLevel = .info
        let directory = data.directory
        let store = try ClosetStore(directory: directory)
        let removed = try await store.collectUnreferencedMedia()
        logger.info("Data directory: \(directory.root.path)")
        if removed > 0 { logger.info("Removed \(removed) unreferenced media files") }
        let configuration = ServerConfiguration(port: port, webRoot: webRoot.map { URL(fileURLWithPath: $0, isDirectory: true) })
        let app = makeApplication(store: store, configuration: configuration, logger: logger)
        logger.info("Closet Manager is available at http://\(ServerConfiguration.host):\(port)/")
        try await app.runService()
    }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "导入 App 导出的 .wardrobe 备份。默认只做预检，加 --apply 才写入。")

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
        let report: ImportReport
        do {
            report = try await BackupImporter(store: store).importBackup(data, mode: restoreMode, dryRun: !apply)
        } catch ImportError.rejected(let rejected) {
            print(try render(rejected))
            throw ExitCode(2)
        }
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
        for issue in report.errors { lines.append("错误 [\(issue.code.rawValue)] \(issue.entity ?? "") \(issue.id ?? "")：\(issue.message)") }
        for issue in report.warnings { lines.append("警告 [\(issue.code.rawValue)] \(issue.entity ?? "") \(issue.id ?? "")：\(issue.message)") }
        return lines.joined(separator: "\n")
    }
}
