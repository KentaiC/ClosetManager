# 架构决策：本地 Web 应用的技术选型

状态为已采用。决策日期 2026-10-07，依据提交 `4c0ed0e` 时的仓库内容。本文只做技术选型与架构决定，不包含实现。审计结论见 `docs/AUDIT_REPORT.zh-CN.md`，迁移过程见 `docs/WEB_MIGRATION.zh-CN.md`。

## 1. 已确认的产品要求

本节编号沿用审计报告第 11 节的 D1 到 D6。`docs/WEB_MIGRATION.zh-CN.md` 第 2 章的决策记录另有一套编号，两者不是同一组。

| 编号 | 要求 | 当前仓库的状态 |
|---|---|---|
| D1 | 只支持 macOS，不需要 Windows 与 Linux | 服务端可在 macOS 14 及以上运行。Linux 只用于 CI 测试，不作为运行平台 |
| D2 | 只允许本机访问，只绑定 `127.0.0.1` | 已满足。`ServerConfiguration.host` 固定为 `"127.0.0.1"`，见 `Server/Sources/ClosetHTTP/ServerApplication.swift:10` |
| D3 | `Deferred — requires product decision` | 本阶段不做同步，保留 iOS App 与备份导入导出，架构为同步留出边界，见第 5 章 |
| D4 | 原图与原图元数据永久保留，原图不以 base64 整体存入数据库 | 数据库中只保存原图的 SHA-256 引用，上传内容按原字节写入文件，见第 2 章 |
| D5 | 没有选择场景的单品不参与智能推荐，不能理解为适用所有场景 | 与当前行为一致，由 `testItemsWithoutScenariosAreExcluded_AuditH01` 固定 |
| D6 | 启动后本地服务启动、只监听本机、自动打开浏览器进入应用，用户不需要手动输入地址 | 服务端与启动脚本已实现自动打开浏览器。启动入口的具体形态尚未确定，见第 2 章 |

## 2. 最终选择

| 项目 | 选择 | 仓库依据 |
|---|---|---|
| 后端语言与运行时 | Swift 6，编译为本机可执行文件 `closet-server`，运行于 macOS 14 及以上 | `Package.swift` 声明 `swift-tools-version:6.0` 与 `platforms: [.macOS(.v14), .iOS(.v17)]`。CI 的 Linux 任务使用 `swift:6.1-noble`，macOS 任务使用 Xcode 26.3 |
| Web 框架 | Hummingbird 2 | `Package.swift` 要求 `from: "2.20.0"`，`Package.resolved` 锁定 2.26.0 |
| 前端 | React 19 与 TypeScript，由 Vite 构建为静态文件，由 `closet-server` 提供 | `Web/package.json` 中 react 19.3.0、typescript 5.9.3、vite 8.3.3。没有使用路由库，路由在 `Web/src/app` 中实现 |
| 数据库 | SQLite，显式 schema 与编号迁移 | `Server/Sources/ClosetStorage/Migrations.swift` 中的迁移 1 与 2，macOS 使用 SDK 自带的 SQLite3 |
| 本地文件 | 数据目录默认位于用户 Application Support 下的 `ClosetManager`，其中有 `closet.sqlite`、`media/`、`backups/`、`tmp/` | `Server/Sources/ClosetStorage/DataDirectory.swift:3-39` |
| 图片存储 | 按内容哈希寻址，路径为 `media/<前两位>/<哈希>.<扩展名>`。`items.original_media` 与 `items.processed_media` 只保存哈希。缩略图等派生图记在 `media_variants` 表中，与原图分开 | `MediaStore.swift:4-7`，`Migrations.swift:63-80`、`:159-166` |
| 原图与元数据 | 上传的原图按原字节写入，不重新编码，因此 EXIF 等元数据随文件保留。派生图另存，不覆盖原图 | `ImageService.swift:55-76` 中 `store.media.write(data)` 写入的是请求中的原始数据 |
| 图片处理 | 直接编译 App 中现有的 `VisionService` 与 `DuplicationDetectorService`，通过 `ImageProcessor` 协议由 `AppleImageProcessor` 调用 | `ClosetManager/Imaging` 编译为 `ClosetImaging` 模块，使用 `VNGenerateForegroundInstanceMaskRequest`、`VNGenerateImageFeaturePrintRequest`、CoreImage 与 ImageIO |
| 本机访问策略 | 只绑定 `127.0.0.1`。端口默认 8765，被占用时依次尝试之后的 9 个端口。请求的 Host 必须是本机，写请求必须带 `X-Closet-Client` 头并且同源 | `LocalLaunch.swift` 中的 `PortSelector`，`Middleware.swift:7-65` 中的 `RequestGuardMiddleware`，`Tests/ClosetHTTPTests/SecurityTests.swift` |
| 浏览器启动 | 服务启动成功后用 `/usr/bin/open` 打开默认浏览器 | `closet-server serve --open`，`LocalLaunch.swift:90-107` 中的 `BrowserOpener`。`scripts/closet` 启动时总是传入 `--open` |
| 启动入口形态 | Repository 中没有足够信息确认这一点。 | 目前的入口是终端命令 `scripts/closet`。D6 要求用户启动应用，但没有指定在 Finder 中双击、登录后自动运行或其它形式，需要你决定 |

## 3. Swift、TypeScript 与 Python 的比较

三个方案的前端相同，都是 `Web/` 中现有的 React 与 TypeScript 代码，差别只在服务端。

| 维度 | A Swift | B TypeScript 与 Node.js | C Python |
|---|---|---|---|
| 1 业务逻辑复用 | 直接复用。`ClosetManager/Core` 共 22 个文件、1,418 行，Xcode 把它编进 App，`Package.swift` 的 `ClosetCore` 目标以同一路径编给服务端。上一阶段的 H-03 修复只改了一处 `ItemLifecycle`，App 与服务端同时生效 | 需要移植 `OutfitGenerationEngine`、`ColorExtraction`、`SimilarityGrouping`、`AnalyticsService`、`TravelService`、`WardrobeSearch` 等规则。iOS App 按 D3 继续保留，同一条规则会有 Swift 与 TypeScript 两份 | 与 B 相同，需要移植，规则会有 Swift 与 Python 两份 |
| 2 数据模型复用 | 备份格式 `WardrobeBackup` 的 DTO 与领域枚举在 Core 中，服务端导入导出直接使用。服务端持久化记录在 `ClosetStorage/Records.swift` | DTO、枚举及其原始值都要重写，并与 App 的 `.wardrobe` 格式逐字段对齐 | 与 B 相同 |
| 3 图片处理复用 | 服务端编译的就是 App 的 `VisionService` 源文件，抠图与相似检测的效果与 App 一致 | Node.js 不能直接调用 Vision。需要另写原生扩展或 Swift 辅助程序，`ClosetManager/Imaging` 的代码不能原样复用 | 可以通过 PyObjC 调用 Vision，但要用 Python 重写调用代码。审计报告 6.3 节指出若改用模型方案，相似检测的阈值 0.6 与 0.30 必须重新标定 |
| 4 Apple Vision 依赖 | D1 只支持 macOS，Vision 一定可用。GitHub CI 的 macOS 任务在提交 `4c0ed0e` 上已经编译到 `ClosetServer`，它依赖的 `ClosetImaging` 与 `ClosetServices` 都编译成功。同一次 CI 的 iOS App 构建也成功 | 依赖额外的桥接层 | 依赖 PyObjC，或改用 ONNX 等模型并随应用提供模型文件 |
| 5 SQLite 持久化 | 已实现。自有封装 `SQLiteDatabase.swift`，有迁移、外键、CHECK 约束，迁移前自动备份数据库 | 有成熟的 SQLite 库，schema SQL 可以照搬，存储层代码需要重写 | 标准库自带 sqlite3，存储层代码需要重写 |
| 6 本地文件 | 已实现按内容寻址的 `MediaStore`、上传登记与垃圾回收、`DataDirectory` 布局 | 需要重写，难度不高 | 需要重写，难度不高 |
| 7 浏览器集成 | 已实现。静态文件、版本化 JSON API `/api/v1`、图片接口都由同一个进程提供 | 优势是前后端可以共享 TypeScript 类型。目前 `Web/src/api` 中的类型与服务端模型是手工对应的 | 与 A 相同，类型需要手工对应 |
| 8 测试 | Swift 测试 192 个，覆盖 Core、存储、服务与 HTTP。另有前端单元测试 109 个、端到端测试 21 个 | 192 个 Swift 服务端测试要用新语言重写。前端与端到端测试可以保留 | 与 B 相同 |
| 9 迁移复杂度 | 服务端已经存在，`Server/Sources` 共 4,312 行，App 的全部页面已能在浏览器中使用。剩余工作是修复 CI 与确定启动入口 | 重写 4,312 行服务端，移植 1,418 行 Core，再加图片处理桥接 | 与 B 相同，图片处理桥接改为 PyObjC |
| 10 维护 | App、Core、服务端都是 Swift，前端是 TypeScript，共两种语言，规则只有一份 | 两种语言，但业务规则有两份，每次修复都要改两处并保持一致 | 三种语言，业务规则有两份 |
| 11 启动与本机要求 | 运行时只需要一个可执行文件与 `Web/dist`。构建时需要 Swift 工具链与 Node.js | 运行时需要安装 Node.js | 运行时需要安装 Python 及其依赖 |
| 12 未来扩展 | Swift 服务端生态较小。`Package.resolved` 中锁定了 24 个包，主要是 swift-nio 系列 | 生态最大 | 图像与机器学习生态最成熟 |
| 13 D3 同步兼容 | App 与服务端共享 Core 中的类型与备份 DTO，将来的同步协议可以只写一份，两端同时编译 | 同步协议要用 Swift 与 TypeScript 各实现一次 | 同步协议要用 Swift 与 Python 各实现一次 |
| 14 是否需要 Apple Developer Program | 不需要，见第 4 章 | 不需要 | 不需要 |

选择 A 的决定性因素有三个。第一个是 D1 只支持 macOS，Vision 在这个前提下没有可移植性问题，现有抠图与相似检测可以原样使用。第二个是 D3 要求保留 iOS App，选 B 或 C 会让每条业务规则出现两份实现，上一阶段 H-03 那样的修复就要做两遍。第三个是服务端已经实现并且有 192 个测试，B 与 C 都要从头重写。

B 的真实优势是前后端类型共享，C 的真实优势是机器学习生态。在 D1 已确定的前提下，这两项都不足以抵消重写与规则分叉的代价。若将来 D1 改为需要支持其它系统，需要重新评估本决定。

## 4. 不依赖 Apple Developer Program

服务端与 Web 前端都不需要付费开发者账号。

`closet-server` 由 SwiftPM 在本机构建，Xcode 或命令行工具即可完成。`Package.swift` 与 `scripts/closet` 中没有任何签名、entitlement、App Store 或 TestFlight 相关配置。本机编译出的程序不带下载产生的隔离属性，Gatekeeper 不会因为缺少公证而阻止运行。Vision、CoreImage、ImageIO 都是 macOS SDK 中的公开 API，服务端以普通用户进程运行。

iOS App 的工程中 `DEVELOPMENT_TEAM` 为空，`CODE_SIGN_STYLE` 为 `Automatic`。你目前用什么方式把 App 安装到 iPhone 上，Repository 中没有足够信息确认这一点。从 iPhone 取出真实数据需要 App 在设备上运行并导出备份，这一步不属于 Web 架构本身，但它是数据迁移的前提。

## 5. 目标架构

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
  与 iOS App 共用同一份源码              ClosetManager/Imaging，即 ClosetImaging
    ↓                                     Vision、CoreImage、ImageIO
Persistence                   Server/Sources/ClosetStorage
  ClosetStore actor，StoreSession 事务，Migrations，MediaStore
    ↓
SQLite 与本地文件
  <数据目录>/closet.sqlite
  <数据目录>/media/<前两位>/<哈希>.<扩展名>，原图、抠图、派生图
  <数据目录>/backups/pre-migration 与 backups/before-import
```

iOS App 与 Web 版的关系如下。

```text
iOS App  SwiftUI 与 SwiftData
  编译同一份 ClosetManager/Core 与 ClosetManager/Imaging
    ↓  导出 .wardrobe 备份文件，版本 1
closet-server import 或 Web 设置页导入
    ↓  严格校验后写入 SQLite 与 media/
Web 版数据目录
```

为 D3 同步预留的边界有两个。一个是版本化的 `/api/v1`，前端不直接接触数据库。另一个是 Core 中的 `WardrobeBackup` DTO，两端用同一份类型描述数据。单品、穿搭、穿着记录都使用 App 生成的 UUID 作为主键，导入不改变标识。

## 6. 迁移策略

### 6.1 直接复用的 Swift 逻辑

`ClosetManager/Core/Rules` 中的穿搭生成、状态流转、取色、相似分组、看板统计、差旅建议、高级筛选与默认值规则。`ClosetManager/Core/Domain` 中的全部领域枚举、颜色命名与 `StoredColor`。`ClosetManager/Core/Backup/WardrobeBackup.swift` 中的备份格式与版本校验。`ClosetManager/Imaging` 中的抠图与相似检测。

### 6.2 必须重新实现的部分

这些部分在之前的迁移阶段已经完成。SwiftUI 页面已用 React 重写，见 `Web/src/features`。SwiftData 持久化在服务端改为显式 SQLite schema。App 的 `BackupService` 导入逻辑在服务端改为更严格的 `BackupImporter`。缩略图与 HEIC 显示转换是服务端新增的处理。

### 6.3 迁移后再处理的部分

| 项目 | 原因 |
|---|---|
| C-01 的流式导出导入与备份格式 v2 | 需要架构决定，见 `docs/WEB_MIGRATION.zh-CN.md` 第 9 章 |
| D3 同步 | 产品决定未定 |
| H-02 天气规则 | 需要产品决定 |
| H-04、H-05、H-06 | 属于 iOS App 内部，需要 Apple 工具链与真机验证 |
| H-01 的提示文字 | D5 已确定行为保持不变。剩下的问题是生成失败时提示指向了错误原因，可以在 Core 中返回结构化原因后修复 |

### 6.4 必须保留在 iOS App 的部分

SwiftUI 界面、SwiftData 模型 `ClothingItem`、`Outfit`、`WearRecord`，以及 App 的备份导出。在 D3 决定之前，App 的备份导出是从 iPhone 取出数据的唯一通道。本阶段不改动 iOS App。

### 6.5 需要抽象为独立领域逻辑的部分

| 项目 | 现状 | 处理时机 |
|---|---|---|
| 备份导入的校验规则 | App 的 `BackupService.apply` 与服务端的 `BackupImporter` 各有一份，服务端更严格 | 设计备份 v2 时放入 Core |
| 生成失败的原因 | 生成结果只给出缺少的分类，不区分缺少的原因 | 修复 H-01 提示时放入 Core 的生成结果 |
| 同步所需的变更记录 | 删除操作没有留下记录，两端无法得知对方删除了什么 | D3 决定后在 Core 中定义 |

## 7. 风险

| 风险 | 说明 | 应对 |
|---|---|---|
| macOS 上的测试尚未通过 | 提交 `4c0ed0e` 的 CI 中，macOS 任务已编译到 `ClosetServer`，但测试文件 `Tests/ClosetHTTPTests/LocalLaunchTests.swift:72` 中的 `bind` 在 Darwin 上被解析为实例方法，测试目标无法编译，因此 Vision 相关代码还没有在 macOS 上运行过测试 | 下一阶段第一步修复 |
| 端到端 CI 失败 | 同一次 CI 中，Swift 容器以 root 身份创建 `Web/e2e/.data`，Playwright 扫描 `e2e` 目录时报 `EACCES`。本机运行的 21 个端到端测试全部通过，失败来自 CI 配置 | 下一阶段第一步修复 |
| 真实照片的抠图与相似检测效果 | 只在 CI 中编译过，没有用真实衣物照片在 Mac 上运行过 | 修复 CI 后在 Mac 上按 `docs/WEB_MIGRATION.zh-CN.md` 第 8 章清单验证 |
| 备份文件体积 | 版本 1 备份把原图与抠图以 base64 写在一个 JSON 中，服务端导入时整体读入内存。D4 要求原图永久保留，备份会持续变大。App 端导出在单品较多时可能失败，这会阻断真实数据迁移 | C-01 的长期方案需要架构决定 |
| 原图元数据中的隐私信息 | 按 D4 保留元数据，照片中的拍摄地点等信息会随原图与备份一起保存和导出 | 属于 D4 的已知后果，导出界面可以加以提示 |
| 两套持久化 | App 使用 SwiftData，服务端使用 SQLite，模型之间靠备份格式对应 | D3 同步时需要定义映射与冲突规则 |
| 构建前提 | 首次启动需要 Swift 工具链与 Node.js，`scripts/closet` 提示需要 Node.js 22 | 启动入口确定后可以改为分发构建好的文件 |
| 端口与浏览器偏好 | 默认端口被占用时会改用其它端口，浏览器中的界面偏好按端口分别保存 | 已在启动提示中说明 |
| Swift 服务端生态 | Hummingbird 与 swift-nio 的升级要跟随 Swift 版本 | 依赖由 `Package.resolved` 锁定，升级时运行全部测试 |
