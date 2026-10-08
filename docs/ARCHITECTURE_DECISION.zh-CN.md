# 架构决策：本地 Web 应用的技术选型

状态为已采用。初次决策日期 2026-10-07，依据提交 `4c0ed0e` 时的仓库内容。2026-10-08 曾把 D3 记为删除 iOS App，随后撤回，D3 恢复为 `Deferred — requires product decision`。本文只做技术选型与架构决定，不包含实现。审计结论见 `docs/AUDIT_REPORT.zh-CN.md`，迁移过程见 `docs/WEB_MIGRATION.zh-CN.md`。

## 1. 产品方向

本次迁移的目标是 macOS 本地 Web 应用。

```text
macOS
  ↓
closet-server
  ↓
127.0.0.1
  ↓
Browser
  ↓
React / TypeScript Web UI
  ↓
Hummingbird / Swift backend
  ↓
SQLite + Local filesystem
```

iOS App 的去留属于 D3，目前为 `Deferred — requires product decision`。当前不删除 iOS App，也没有删除它的计划，将来是否删除保持未决定。不实现 iOS 与 Web 之间的自动同步。

不购买 Apple Developer Program。Web 应用在本机构建、在本机运行，不受这一点影响，见第 5 章。Web 应用运行时不需要 Xcode。

共享核心对 Web 服务端有价值，这是它保留的理由。架构中不为 iOS 设计额外的抽象。

## 2. 已确认的产品要求

本节编号沿用审计报告第 11 节的 D1 到 D6。`docs/WEB_MIGRATION.zh-CN.md` 第 2 章的决策记录另有一套编号，两者不是同一组。

| 编号 | 要求 | 当前仓库的状态 |
|---|---|---|
| D1 | 只支持 macOS，不需要 Windows 与 Linux | 服务端可在 macOS 14 及以上运行。Linux 只用于 CI 测试，不作为运行平台 |
| D2 | 只允许本机访问，只绑定 `127.0.0.1` | 已满足。`ServerConfiguration.host` 固定为 `"127.0.0.1"`，见 `Server/Sources/ClosetHTTP/ServerApplication.swift:10` |
| D3 | `Deferred — requires product decision` | 当前不删除 iOS App，没有删除计划，将来是否删除未决定。不实现 iOS 与 Web 的自动同步 |
| D4 | 原图与原图元数据永久保留，原图不以 base64 整体存入数据库 | 数据库中只保存原图的 SHA-256 引用，上传内容按原字节写入文件，见第 3 章 |
| D5 | 没有选择场景的单品不参与智能推荐，不能理解为适用所有场景 | 与当前行为一致，由 `testItemsWithoutScenariosAreExcluded_AuditH01` 固定 |
| D6 | 启动后本地服务启动、只监听本机、自动打开浏览器进入应用，用户不需要手动输入地址 | 最小启动流程已实现，入口是终端命令 `scripts/closet`。浏览器在服务开始监听之后才打开，判断依据是 Hummingbird 的 `onServerRunning` 回调。2026-10-08 用 `scripts/closet start` 验证：浏览器命令被调用时 `/api/v1/health` 已返回 200；端口被占用或数据目录无效时以退出码 1 结束，不打开浏览器；没有可用的浏览器命令时服务继续运行并提示手动访问已打印的地址 |

## 3. 最终选择

| 项目 | 选择 | 仓库依据 |
|---|---|---|
| 后端语言与运行时 | Swift 6，编译为本机可执行文件 `closet-server`，运行于 macOS 14 及以上 | `Package.swift` 声明 `swift-tools-version:6.0`。`platforms` 中的 `.iOS(.v17)` 供 iOS App 共用源码。CI 的 Linux 任务使用 `swift:6.1-noble`，macOS 任务使用 Xcode 26.3 |
| Web 框架 | Hummingbird 2 | `Package.swift` 要求 `from: "2.20.0"`，`Package.resolved` 锁定 2.26.0 |
| 前端 | React 19 与 TypeScript，由 Vite 构建为静态文件，由 `closet-server` 提供 | `Web/package.json` 中 react 19.3.0、typescript 5.9.3、vite 8.3.3。没有使用路由库，路由在 `Web/src/app` 中实现 |
| 数据库 | SQLite，显式 schema 与编号迁移 | `Server/Sources/ClosetStorage/Migrations.swift` 中的迁移 1 与 2，macOS 使用 SDK 自带的 SQLite3 |
| 本地文件 | 数据目录默认位于用户 Application Support 下的 `ClosetManager`，其中有 `closet.sqlite`、`media/`、`backups/`、`tmp/` | `Server/Sources/ClosetStorage/DataDirectory.swift:3-39` |
| 图片存储 | 按内容哈希寻址，路径为 `media/<前两位>/<哈希>.<扩展名>`。`items.original_media` 与 `items.processed_media` 只保存哈希。缩略图等派生图记在 `media_variants` 表中，与原图分开 | `MediaStore.swift:4-7`，`Migrations.swift:63-80`、`:159-166` |
| 原图与元数据 | 上传的原图按原字节写入，不重新编码，因此 EXIF 等元数据随文件保留。派生图另存，不覆盖原图 | `ImageService.swift:55-76` 中 `store.media.write(data)` 写入的是请求中的原始数据 |
| 图片处理 | 服务端直接编译现有的 `VisionService` 与 `DuplicationDetectorService`，通过 `ImageProcessor` 协议由 `AppleImageProcessor` 调用 | `ClosetManager/Imaging` 编译为 `ClosetImaging` 模块，使用 `VNGenerateForegroundInstanceMaskRequest`、`VNGenerateImageFeaturePrintRequest`、CoreImage 与 ImageIO |
| 本机访问策略 | 只绑定 `127.0.0.1`。端口默认 8765，被占用时依次尝试之后的 9 个端口。请求的 Host 必须是本机，写请求必须带 `X-Closet-Client` 头并且同源 | `LocalLaunch.swift` 中的 `PortSelector`，`Middleware.swift:7-65` 中的 `RequestGuardMiddleware`，`Tests/ClosetHTTPTests/SecurityTests.swift` |
| 浏览器启动 | 服务启动成功后用 `/usr/bin/open` 打开默认浏览器 | `closet-server serve --open`，`LocalLaunch.swift:90-107` 中的 `BrowserOpener`。`scripts/closet` 启动时总是传入 `--open` |
| 启动入口形态 | 终端命令 `scripts/closet` | `scripts/closet start` 依次构建前端与服务端，然后以 `exec` 运行 `closet-server serve --web-root Web/dist --open`，不留下后台进程。Finder 双击、登录后自动运行、`.app` 等形态不在本次范围内 |
| 运行时需求 | 运行时只需要 `closet-server` 可执行文件与 `Web/dist`，不需要 Xcode | 构建时 `scripts/closet` 需要 Swift 工具链，提示文字为「在 macOS 上安装 Xcode 或命令行工具即可」，构建前端需要 Node.js 22。CI 的 macOS 任务使用 Xcode 构建。只安装命令行工具能否完成构建，Repository 中没有足够信息确认这一点 |

## 4. Swift、TypeScript 与 Python 的比较

三个方案的前端相同，都是 `Web/` 中现有的 React 与 TypeScript 代码，差别只在服务端。D3 目前未决定，下表各行都不以 D3 的结果为前提。

| 维度 | A Swift | B TypeScript 与 Node.js | C Python |
|---|---|---|---|
| 1 业务逻辑复用 | 直接复用。`ClosetManager/Core` 共 22 个文件、1,418 行，已由 `Package.swift` 的 `ClosetCore` 目标编给服务端，Xcode 也把它编进 App，可以逐项对照 App 的行为 | 需要移植 `OutfitGenerationEngine`、`ColorExtraction`、`SimilarityGrouping`、`AnalyticsService`、`TravelService`、`WardrobeSearch` 等规则，并重新证明与现有行为一致。iOS App 继续存在时，同一条规则会有两份 | 与 B 相同，需要移植并重新证明一致 |
| 2 数据模型复用 | 备份格式 `WardrobeBackup` 的 DTO 与领域枚举在 Core 中，服务端导入导出直接使用。服务端持久化记录在 `ClosetStorage/Records.swift` | DTO、枚举及其原始值都要重写，并与现有 `.wardrobe` 格式逐字段对齐。iPhone 上的数据只能通过这个格式迁出 | 与 B 相同 |
| 3 图片处理复用 | 服务端编译的就是现有的 `VisionService` 源文件，抠图与相似检测的算法与 App 相同 | Node.js 不能直接调用 Vision。需要另写原生扩展或 Swift 辅助程序，`ClosetManager/Imaging` 的代码不能原样复用 | 可以通过 PyObjC 调用 Vision，但要用 Python 重写调用代码。审计报告 6.3 节指出若改用模型方案，相似检测的阈值 0.6 与 0.30 必须重新标定 |
| 4 Apple Vision 依赖 | D1 只支持 macOS，Vision 一定可用。GitHub CI 的 macOS 任务在提交 `8b9fce6` 上完成构建并运行了 192 个测试。这些测试没有调用 Vision，见第 8 章 | 依赖额外的桥接层 | 依赖 PyObjC，或改用 ONNX 等模型并随应用提供模型文件 |
| 5 SQLite 持久化 | 已实现。自有封装 `SQLiteDatabase.swift`，有迁移、外键、CHECK 约束，迁移前自动备份数据库 | 有成熟的 SQLite 库，schema SQL 可以照搬，存储层代码需要重写 | 标准库自带 sqlite3，存储层代码需要重写 |
| 6 本地文件 | 已实现按内容寻址的 `MediaStore`、上传登记与垃圾回收、`DataDirectory` 布局 | 需要重写，难度不高 | 需要重写，难度不高 |
| 7 浏览器集成 | 已实现。静态文件、版本化 JSON API `/api/v1`、图片接口都由同一个进程提供 | 优势是前后端可以共享 TypeScript 类型。目前 `Web/src/api` 中的类型与服务端模型是手工对应的 | 与 A 相同，类型需要手工对应 |
| 8 测试 | Swift 测试 192 个，覆盖 Core、存储、服务与 HTTP。另有前端单元测试 109 个、端到端测试 21 个 | 192 个 Swift 服务端测试要用新语言重写。前端与端到端测试可以保留 | 与 B 相同 |
| 9 迁移复杂度 | 服务端已经存在，`Server/Sources` 共 4,312 行，App 的全部页面已能在浏览器中使用 | 重写 4,312 行服务端，移植 1,418 行 Core，再加图片处理桥接 | 与 B 相同，图片处理桥接改为 PyObjC |
| 10 维护 | App、Core、服务端是 Swift，前端是 TypeScript，规则只有一份 | 服务端与前端同为 TypeScript。iOS App 继续存在时还有 Swift，规则有两份 | 服务端是 Python，前端是 TypeScript。iOS App 继续存在时还有 Swift，规则有两份 |
| 11 启动与本机要求 | 运行时只需要一个可执行文件与 `Web/dist`。构建时需要 Swift 工具链与 Node.js | 运行时需要安装 Node.js | 运行时需要安装 Python 及其依赖 |
| 12 未来扩展 | Swift 服务端生态较小。`Package.resolved` 中锁定了 24 个包，主要是 swift-nio 系列 | 生态最大 | 图像与机器学习生态最成熟 |
| 13 D3 同步兼容 | D3 未决定，目前不做自动同步。若将来需要同步，App 与服务端可以共用 Core 中的类型与备份 DTO | 同步协议要用 Swift 与 TypeScript 各实现一次 | 同步协议要用 Swift 与 Python 各实现一次 |
| 14 是否需要 Apple Developer Program | 不需要，见第 5 章 | 不需要 | 不需要 |

选择 A 的理由有三点，都不以 D3 的结果为前提。第一点是 D1 只支持 macOS，Vision 在这个前提下没有可移植性问题，现有抠图与相似检测可以原样使用。第二点是服务端与 Core 已经实现并且有 192 个测试，B 与 C 都要从头重写，而用来证明行为一致的参照恰好就是这些 Swift 代码。第三点是 iPhone 上的数据要通过版本 1 的 `.wardrobe` 文件迁出，A 的导入使用的就是 App 导出时所用的同一份 DTO。

B 的真实优势是前后端类型共享，C 的真实优势是机器学习生态。在 D1 已确定、服务端已经完成的前提下，这两项都不足以抵消重写的代价。若将来 D1 改为需要支持其它系统，需要重新评估本决定。

## 5. 不依赖 Apple Developer Program

Web 应用不需要付费开发者账号。

`closet-server` 由 SwiftPM 在本机构建。`Package.swift` 与 `scripts/closet` 中没有任何签名、entitlement、App Store 或 TestFlight 相关配置。本机编译出的程序不带下载产生的隔离属性，Gatekeeper 不会因为缺少公证而阻止运行。Vision、CoreImage、ImageIO 都是 macOS SDK 中的公开 API，服务端以普通用户进程运行。

若 iPhone 上存有真实数据，需要用现有 App 导出 `.wardrobe` 备份，再导入 Web 版。这台设备上的 App 现在能否运行，Repository 中没有足够信息确认这一点。

## 6. 目标架构

```text
Browser
  默认浏览器，访问 http://127.0.0.1:<端口>/，由 closet-server 启动后自动打开
    ↓
Web UI                        Web/src，React 19 与 TypeScript
  只通过 /api/v1 访问数据，枚举名称与阈值来自 /api/v1/meta
    ↓  JSON 请求，图片上传
API / Application boundary    Server/Sources/ClosetHTTP
  Hummingbird 路由，RequestGuardMiddleware 校验 Host、Origin 与 X-Closet-Client
  APIModels 与 APIRequests 定义对外格式，错误统一转换为 JSON
    ↓
Application services          Server/Sources/ClosetServices
  ItemService、LifecycleService、OutfitService、ImageService、InsightService
  BackupImporter、BackupExporter、SettingsService
    ↓                                  ↘
Business Logic                         Image processing
  ClosetManager/Core，即 ClosetCore      ImageProcessor 协议，AppleImageProcessor
  iOS App 也编译这份源码                 ClosetManager/Imaging，即 ClosetImaging
    ↓                                     Vision、CoreImage、ImageIO
Persistence                   Server/Sources/ClosetStorage
  ClosetStore actor，StoreSession 事务，Migrations，MediaStore
    ↓
SQLite 与本地文件
  <数据目录>/closet.sqlite
  <数据目录>/media/<前两位>/<哈希>.<扩展名>，原图、抠图、派生图
  <数据目录>/backups/pre-migration 与 backups/before-import
```

目前不实现自动同步，`/api/v1` 只服务于 Web UI。

现有数据通过备份文件从 App 迁到 Web 版。

```text
iOS App  SwiftUI 与 SwiftData
    ↓  导出 .wardrobe 备份文件，版本 1
closet-server import 或 Web 设置页导入
    ↓  严格校验后写入 SQLite 与 media/
Web 版数据目录
```

导入后单品、穿搭、穿着记录保留 App 生成的 UUID。是否需要反向导入或持续同步取决于 D3。

## 7. 迁移策略

### 7.1 直接复用的 Swift 逻辑

`ClosetManager/Core/Rules` 中的穿搭生成、状态流转、取色、相似分组、看板统计、差旅建议、高级筛选与默认值规则。`ClosetManager/Core/Domain` 中的全部领域枚举、颜色命名与 `StoredColor`。`ClosetManager/Core/Backup/WardrobeBackup.swift` 中的备份格式与版本校验。`ClosetManager/Imaging` 中的抠图与相似检测。

这些源码在物理上位于 `ClosetManager/` 目录下，这个目录也是 iOS App 的源码目录。若将来决定删除 iOS App，它们要先迁出到服务端的目录结构中，不能随 App 一起删除。

### 7.2 已经重新实现的部分

这些部分在之前的迁移阶段已经完成。SwiftUI 页面已用 React 重写，见 `Web/src/features`。SwiftData 持久化在服务端改为显式 SQLite schema。App 的 `BackupService` 导入逻辑在服务端改为更严格的 `BackupImporter`。缩略图与 HEIC 显示转换是服务端新增的处理。

### 7.3 迁移后再处理的部分

| 项目 | 处理方式 |
|---|---|
| C-01 的流式导出导入与备份格式 v2 | 需要架构决定，见 `docs/WEB_MIGRATION.zh-CN.md` 第 9 章 |
| H-02 天气规则 | 需要产品决定 |
| H-01 的提示文字 | D5 已确定行为保持不变。剩下的问题是生成失败时提示指向了错误原因，可以在 Core 中返回结构化原因后修复 |
| H-04、H-05、H-06 | 只涉及 iOS App 内部，需要 Apple 工具链与真机验证，暂缓 |

### 7.4 iOS App 的角色

iOS App 保留在仓库中，继续编译同一份 Core。Web 迁移以它作为行为参照，它的备份导出也是从 iPhone 取出数据的途径。本阶段不改动 iOS App，CI 中的 iOS 构建任务继续保留。

### 7.5 需要放入 Core 的领域逻辑

| 项目 | 现状 | 处理时机 |
|---|---|---|
| 备份导入的校验规则 | App 的 `BackupService.apply` 与服务端的 `BackupImporter` 各有一份，服务端更严格 | 设计备份 v2 时决定 |
| 生成失败的原因 | 生成结果只给出缺少的分类，不区分缺少的原因 | 修复 H-01 提示时放入 Core 的生成结果 |
| 同步所需的变更记录 | 删除操作没有留下记录 | 只在 D3 决定需要同步时才定义 |

## 8. 风险

| 风险 | 说明 | 应对 |
|---|---|---|
| Vision 运行时没有自动化测试 | Vision runtime on macOS is still not covered by automated tests. GitHub CI 在提交 `8b9fce6` 上的 macOS 任务运行了 192 个测试，全部通过，但测试一律注入 `UnavailableImageProcessor` 或 `FakeImageProcessor`，`AppleImageProcessor`、`VisionService`、`DuplicationDetectorService` 只经过编译 | 在 macOS 上用真实照片验证，或在 macOS CI 中增加最小的运行测试，需要另行决定 |
| 共享代码位于 iOS 源码目录内 | `ClosetManager/Core` 与 `ClosetManager/Imaging` 位于 iOS 源码目录内，服务端依赖它们 | 若将来删除 iOS App，先迁出这两个目录并更新 `Package.swift` |
| iPhone 数据迁出 | 真实数据若只存在于 iPhone，必须用现有 App 导出 | 在 Mac 上导入并核对，见 `docs/WEB_MIGRATION.zh-CN.md` 第 8 章 |
| 两套持久化 | App 使用 SwiftData，服务端使用 SQLite，模型之间靠备份格式对应 | D3 决定需要同步时再定义映射与冲突规则 |
| 备份文件体积 | 版本 1 备份把原图与抠图以 base64 写在一个 JSON 中，服务端导入时整体读入内存。App 端导出在单品较多时可能失败，这会阻断真实数据迁移 | C-01 的长期方案需要架构决定 |
| 原图元数据中的隐私信息 | 按 D4 保留元数据，照片中的拍摄地点等信息会随原图与备份一起保存和导出 | 属于 D4 的已知后果，导出界面可以加以提示 |
| 构建前提 | 首次启动需要 Swift 工具链与 Node.js，`scripts/closet` 提示需要 Node.js 22。只安装命令行工具能否构建尚未验证 | 启动入口确定后可以改为分发构建好的文件 |
| 端口与浏览器偏好 | 默认端口被占用时会改用其它端口，浏览器中的界面偏好按端口分别保存 | 已在启动提示中说明 |
| Swift 服务端生态 | Hummingbird 与 swift-nio 的升级要跟随 Swift 版本 | 依赖由 `Package.resolved` 锁定，升级时运行全部测试 |

初次决策时记录的两项 CI 失败已经修复。macOS 测试编译失败由提交 `f66cc38` 修复，端到端测试的权限失败由提交 `8b9fce6` 修复。GitHub CI 运行 37689208064 在提交 `8b9fce6` 上的 5 个任务全部通过。
