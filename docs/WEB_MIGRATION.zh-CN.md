# Local Web Application 迁移记录

本文记录 Closet Manager 从 iOS 应用逐步改造为本地 Web 应用的决策、架构与进度。审计结论见上一轮的审计报告，本文只记录实施过程中的事实。

## 1. 目标形态

```text
Browser
  → Web UI          Web/，浏览器单页应用
  → Backend         Server/，本机 Swift 服务进程，只监听 127.0.0.1
  → Business Logic  ClosetManager/Core，与 iOS App 共用同一份源码
  → Database        SQLite 文件
  → File Storage    本机数据目录中的图片与备份
```

iOS App 保持可编译、可运行，与 Web 版共用 `ClosetManager/Core` 中的业务规则。

## 2. 决策记录

| 编号 | 决策 | 依据 | 状态 |
|---|---|---|---|
| D1 | 服务端使用 Swift | 迁移要求写明不要无理由更换现有技术栈，并尽可能复用现有业务逻辑。现有逻辑全部是 Swift。抠图与相似检测依赖 Apple Vision，因此这两项能力只在 macOS 14 及以上提供；服务端其余部分在 Linux 上也能编译和测试 | 已采用，若需要在 Windows 或 Linux 上正式运行需重新评估 |
| D2 | 只监听 127.0.0.1，不提供局域网访问 | 安全基线。局域网访问属于新增能力，需要另行决定 | 已采用 |
| D3 | iOS App 保留，共享逻辑只有一份源码 | 迁移要求不得删除现有功能，并保持现有功能可运行 | 已采用；双向同步不在当前范围 |
| D4 | 保留原图，导入数据不改变含义 | 迁移要求不得改变现有数据含义 | 已采用；原图元数据如何处理仍待决定 |
| D5 | 未勾选场景的单品如何处理 | Repository 中没有依据 | 待决定。当前行为已由测试 `testItemsWithoutScenariosAreExcluded_AuditH01` 固定 |
| D6 | 启动方式 | 终端命令是任何形态都需要的最小形态 | 已实现终端命令 `scripts/closet`，见第七阶段；登录后自动运行、容器等其它形态待决定 |
| D7 | 服务端持久化使用 SQLite 显式 schema，不复用 SwiftData | SwiftData 无法在 Linux 上编译测试；它没有 CHECK、外键、部分唯一索引这类约束，也没有可审查的迁移脚本（审计 H-05）。SwiftData 本身就以 SQLite 为底层存储，这里只是改为直接使用，不属于更换技术栈 | 已采用 |
| D8 | 服务端导入比 App 更严格 | App 遇到无法识别的取值会静默替换为默认值（审计 M-02），这会改变数据含义。服务端改为报错并拒绝导入；能在不改变含义的前提下处理的问题记为警告 | 已采用 |

## 3. 共享核心的组织方式

`ClosetManager/Core` 位于 iOS 工程的文件系统同步分组内，Xcode 把其中的文件编译进 App 模块；根目录 `Package.swift` 的 `ClosetCore` 目标以同一路径把它们编译成独立模块，供服务端使用。

选择这种方式的原因有两个。

第一，不需要修改 `project.pbxproj`。开发文档要求本地对该文件执行 `git update-index --skip-worktree`，对它的任何上游改动都会给本地拉取带来冲突。

第二，持久化类型留在 App 模块内。`Category`、`StoredColor` 等类型被 SwiftData 模型直接使用。若把它们移到另一个模块，类型的模块归属会改变，SwiftData 对此的处理方式 Repository 中没有足够信息确认，存在已有数据无法读取的风险。当前方式下类型名、模块、原始值都不变。

Core 只允许依赖 Foundation。SwiftUI 桥接放在 App 内，例如 `ClosetManager/Models/Support/StoredColor+SwiftUI.swift`。

`ClosetManager/Imaging` 用同样的方式共享 App 中调用 Vision、CoreImage、ImageIO 的代码，即 `VisionService` 与 `DuplicationDetectorService`。SwiftPM 把它编译成 `ClosetImaging` 模块。文件整体包在 `#if canImport(Vision)` 中，Linux 上是空模块。其中的取色与相似分组规则属于纯计算，放在 Core 的 `ColorExtraction` 与 `SimilarityGrouping` 中。

## 4. Roadmap 调整

| 编号 | 调整 | 原因 |
|---|---|---|
| R1 | Apple 工具链上的编译验证延后，改用 Linux 验证环境作为替代 | 本会话推送到 GitHub 时返回 403，CI 无法触发。替代验证把 Core 与剥离 SwiftData 宏的模型文件编进同一模块做类型检查，并把重构前后的算法放在同一随机序列下逐项比较 |
| R2 | 行为缺陷修复单独成轨，不混入迁移阶段 | 迁移要求保持现有功能与数据含义。审计报告中的 H-01、H-02、M-01、M-04、M-07、M-17 等问题保持现状，已有特征测试的会在修复时显式改变断言。修复放在共享核心中进行，App 与 Web 同时生效。例外见 R4。H-03 已在稳定化阶段修复，见第 9 章 |
| R3 | 审计报告 Phase 0 中的「测试与 CI」提前到第一阶段完成 | 后续每一步都需要回归基线 |
| R4 | Web 版只在两种情况下与 App 行为不同 | 一是安全需要。二是 App 写入的数据与模型注释定义的含义矛盾。其余一律与 App 一致，差异逐条列在下表 |
| R5 | 第五阶段不建持久化任务队列，图片处理在请求内完成，批量录入由浏览器逐张提交 | 审计 Phase 4.2 建议任务队列。本地只有一个用户，App 本身也是逐张串行处理。请求内处理已经能给出逐张进度与失败清单，也没有队列的恢复与清理问题。若真实数据下单张处理时间过长，再引入队列 |
| R6 | macOS 专用的图像代码在本环境无法编译和运行，验证延后到 macOS | 本环境只有 Linux。为降低风险，服务端直接编译 App 现有的 `VisionService` 源文件，不另写一份。新增的 Apple API 调用只有缩略图与格式转换两处。其余逻辑通过协议隔离，在 Linux 上用替身实现测试。CI 的 macOS 任务会编译这部分代码，但推送受阻，见 R1 |

Web 版与 App 的有意差异如下。界面形式上的差异，例如删除前增加确认对话框，不在此列。

| 位置 | App 的行为 | Web 版的行为 | 依据 |
|---|---|---|---|
| 备份导入 | 无法识别的枚举值静默替换为默认值 | 整个文件拒绝导入并报告位置 | D8，审计 M-02 |
| 自由拼搭收藏 | 来源记为「算法生成」 | 来源记为「手动拼搭」 | `OutfitSource` 的定义，审计 M-05 |
| 智能生成收藏 | 记录点击收藏时界面上的场景与保暖档位 | 记录生成这批草稿时的条件 | `Outfit.targetScenario` 注释为「生成时的目标场景」 |

## 5. 服务端结构

```text
Server/Sources/
  CSQLite          Linux 上的系统 SQLite 模块映射
  ClosetStorage    SQLite 封装、迁移、存储 actor、按内容寻址的图片存储、上传记录与派生图缓存
  ClosetServices   应用服务：备份导入导出、查询、单品新增与编辑、图片上传与处理、穿着流转、穿搭、看板与筛选、差旅、设置
  ClosetHTTP       Hummingbird 路由、API 模型、安全中间件
  ClosetServer     命令行入口 closet-server
```

依赖方向为 ClosetServer → ClosetHTTP → ClosetServices → ClosetStorage → ClosetCore。ClosetServices 还依赖 ClosetImaging。平台相关的图片处理通过 `ImageProcessor` 协议隔离：macOS 上是 `AppleImageProcessor`，其它平台是 `UnavailableImageProcessor`，它只校验并保存上传的图片。

服务端数据目录中的 `backups/pre-migration` 存放 schema 升级前的数据库副本，`backups/before-import` 存放导入备份前自动导出的当前数据，保留最近五份。

开发时的常用命令如下，`--data-dir` 省略时使用用户的应用数据目录。

```bash
swift run closet-server import 备份.wardrobe --data-dir ./data            # 只做预检
swift run closet-server import 备份.wardrobe --data-dir ./data --apply    # 写入
swift run closet-server serve --data-dir ./data --port 8765
```

## 6. 前端结构

```text
Web/
  src/api         API 客户端、与服务端对应的类型、资源加载 hook
  src/app         路由、元数据查找、反馈组件、对话框、提示、数据版本、外观与本地偏好
  src/components  跨页面复用的组件，如胶囊选择组与缩略图行
  src/features    按页面划分的功能，与 App 的 Views 目录一一对应；items 为单件录入、批量录入与相似单品清理
  e2e             Playwright 端到端测试
```

前端不定义任何枚举的中文名称或业务阈值，全部来自 `/api/v1/meta`。界面偏好只保存在当前浏览器，键名沿用 App 的 `@AppStorage` 键，包括 `galleryItemSize`、`ui.accent`、`ui.appearance`、`ui.cornerRadius`。个人资料属于数据，保存在服务端。

写操作成功后调用 `useDataVersion().invalidate()`，所有依赖数据版本的页面重新加载。这对应 App 中 SwiftData 的 `@Query` 在数据变化后自动刷新。

页面通过 `useCapabilities()` 读取服务端的图片处理能力，决定是否提示「当前服务不支持本地抠图」之类的信息。

端到端测试分两个 Playwright 项目。`read-only` 只读取样例数据；`workflows` 依赖它，按顺序修改同一份数据，模拟一次完整使用。

开发与测试命令如下。

```bash
cd Web && npm ci
npm run dev        # Vite 开发服务器，/api 转发到 127.0.0.1:8765
npm test           # 单元测试
npm run build      # 类型检查并构建到 Web/dist
npm run e2e        # 启动 closet-server（导入样例备份）并用 Chromium 测试
```

## 7. 阶段进度

### 第一阶段 Architecture preparation

| 提交 | 内容 |
|---|---|
| `ci: add iOS app build check on macOS runners` | 在未改动的代码上建立 iOS 编译基线 |
| `refactor(core): move platform-independent domain files into ClosetManager/Core` | 纯文件移动 |
| `refactor(core): expose shared domain as the ClosetCore Swift package` | 公开访问级别、拆分 SwiftUI 桥接、`Package.swift`、特征测试、CI 中的 SwiftPM 测试 |
| `refactor(core): share outfit generation and analytics through ClosetCore` | 泛型生成引擎与统计、App 侧适配、引擎测试 |

验证结果。Linux 上 `swift test` 共 43 个测试全部通过。替代验证环境中，重构前后生成器在 19,200 次调用下输出逐项一致，统计输出一致，视图层调用表达式通过类型检查。iOS 工程在 Apple 工具链上的编译尚未验证，原因见 R1。

### 第二阶段 Backend/API boundary

| 提交 | 内容 |
|---|---|
| `refactor(core): share the .wardrobe backup format and item defaults` | 备份格式与默认值规则移入共享核心，App 的 `BackupService` 与 `ClothingItem` 改为引用它们 |
| `feat(server): add SQLite storage layer with migrations and media store` | 存储层 |
| `feat(server): add backup importer and read-only catalog service` | 导入器与只读查询 |
| `feat(server): add loopback-only HTTP API and closet-server CLI` | 只读 API、安全中间件、命令行入口 |

验证结果。Linux 上 `swift test` 共 98 个测试全部通过。替代验证环境中，App 的备份导出在改动前后语义一致，导出后覆盖导入再导出内容不变；App 导出的文件被服务端导入器完整读取。真实运行时，伪造 Host 头的请求返回 403，缺少客户端头的写请求返回 403，非回环地址无法连接。

遗留问题如下。导入时整个备份文件会读入内存，与 App 相同，体积很大的备份需要改为流式解析。Linux 上没有 Vision，服务端在 Linux 运行时不具备抠图与相似检测能力，`/api/v1/health` 中的 `capabilities` 如实返回。HEIC 原图在多数浏览器中无法显示，转码放在第五阶段。目前 API 只读。

### 第三阶段 Web UI foundation

| 提交 | 内容 |
|---|---|
| `feat(server): serve the web UI with single-page fallback` | 服务端托管 `Web/dist`，深链接回退到 `index.html`，静态资源缓存策略 |
| `feat(web): add the Web UI foundation with a read-only wardrobe` | 前端工程、API 客户端、路由、外壳、衣橱只读页面、单品只读详情、单元测试与端到端测试、CI |

验证结果。Swift 测试 103 个、前端单元测试 24 个、端到端测试 6 个全部通过。端到端测试在 Chromium 中运行真实服务，期间页面没有脚本错误，也没有 CSP 拦截。

遗留问题如下。洗衣房、穿搭、日历、看板、设置仍是占位页面，第四阶段迁移。本容器内通过 Docker 包装启动服务时，测试结束后容器不会自动退出，需要手动清理；直接运行 `swift run` 不受影响，CI 中增加了清理步骤。

### 第四阶段 Existing functionality migration

| 提交 | 内容 |
|---|---|
| `feat(core): add lifecycle, packing and search rules for the server` | 状态流转、打包建议、高级筛选规则移入共享核心 |
| `feat(server): migrate the app's write and computed features to the API` | 写接口与计算接口：单品编辑与删除、穿着、脱下、洗净、收藏、生成、看板、筛选、差旅、个人资料 |
| `feat(server): expose warmth level score ranges in API metadata` | 元数据增加每个保暖档位的分数范围，前端不再重复阈值 |
| `feat(web): wear lifecycle, laundry, calendar and item editing` | 脱下穿搭、洗衣房、日历、单品编辑与删除，以及 API 客户端、数据版本、对话框、提示等公共部分 |
| `feat(web): outfits, dashboard, search, travel and settings pages` | 穿搭三个子页、看板、高级筛选、差旅打包、设置 |
| `test(web): end-to-end workflows against the real server` | 在真实服务上按顺序走完一次完整使用流程 |

验证结果。Swift 测试 135 个、前端单元测试 88 个、端到端测试 15 个全部通过。端到端测试期间页面没有脚本错误、控制台错误或 CSP 拦截。两个前端提交分别单独做过类型检查、单元测试与构建。界面在 1200 与 390 像素宽度、浅色与深色模式下截图检查过。

App 中除下列功能外，其余页面均已可在浏览器中使用。

| 尚未迁移 | 原因 | 计划 |
|---|---|---|
| 单件录入、相册与文件批量录入 | 依赖图片上传与处理 | 第五阶段 |
| 编辑页的图片区 | 同上 | 第五阶段 |
| 生成、分享与导入备份 | 依赖浏览器文件上传与下载 | 第五阶段。目前可用 `closet-server import` 导入 |
| 清理相似衣物 | 依赖 Vision，只在 macOS 上可用 | 第五阶段，Linux 上按 `capabilities` 隐藏 |

遗留问题如下。App 侧的 `WearService`、`TravelCapsuleView`、`WardrobeSearchView` 仍使用各自的实现，尚未改为调用共享核心中的同名规则。两者的一致性已在替代验证环境中比较过，切换需要先在 Apple 工具链上编译验证，见 R1。看板热力图与日历按自然日汇总，服务端用本机日历，浏览器用本地时区，两者在同一台电脑上一致。若将来允许从其他设备访问，需要改为由浏览器传入时区。多个浏览器标签页之间不会实时同步，切换页面或重新打开时才会刷新。样例备份中的下装没有适用场景，未改动的样例无法生成穿搭，端到端测试先在编辑页补上场景再生成，这与审计 H-01 一致。

### 第五阶段 File workflow migration

仓库中没有任何 PDF 相关的功能或文件处理。本阶段的文件工作流是图片与 `.wardrobe` 备份文件。

计划按以下顺序提交，每一步单独可审查。

| 步骤 | 内容 |
|---|---|
| 5.1 | 取色与相似分组的规则移入共享核心，App 的 `VisionService` 与 `DuplicationDetectorService` 改为调用它们 |
| 5.2 | App 中与平台框架打交道的图像代码移到 `ClosetManager/Imaging`，App 与服务端编译同一份源文件；服务端只在 macOS 上启用 |
| 5.3 | 图片上传：大小与像素上限、按文件头识别格式、只接受 JPEG、PNG、HEIC、HEIF、WebP；抠图与取色；新增单品；编辑时更换图片；浏览器无法显示的格式与缩略图按需生成派生图 |
| 5.4 | 备份经浏览器导出与导入，导入先预检；覆盖导入前自动保存一份当前数据的备份 |
| 5.5 | 相似单品检测，只在 macOS 上提供 |
| 5.6 | 前端：单件录入、批量录入、设置页的备份与相似单品清理 |

原图按收到的字节原样保存，与 App 相同，元数据不做处理，等待决策 D4。抠图结果与派生图由图像框架重新编码生成。在 Linux 上运行时没有图像解码能力，上传的图片会通过格式与尺寸校验后保存，但不做抠图与取色，主色需要在表单中手动选择，HEIC 图片在多数浏览器中无法显示。

实际提交如下。

| 提交 | 内容 |
|---|---|
| `docs: plan stage 5 file workflows and record roadmap adjustments` | 本节计划与 R5、R6 |
| `feat(core): share colour extraction and similarity grouping rules` | 5.1 |
| `refactor(imaging): share the App's Vision pipeline with the server on macOS` | 5.2 |
| `feat(storage): track uploads and cache derived images` | schema 迁移 2：上传记录与派生图缓存 |
| `feat(server): image uploads, processing and new items` | 5.3 的服务层 |
| `feat(server): HTTP endpoints for uploads, new items and similar items` | 5.3 与 5.5 的接口 |
| `feat(server): backup export and safe restore` | 5.4 的服务层，命令行导入也改为先自动备份 |
| `feat(server): backup export and import over HTTP` | 5.4 的接口 |
| `feat(web): add items from photos, one at a time or in batches` | 5.6 的录入部分 |
| `feat(web): backup export and import, and similar-item cleanup` | 5.6 的设置部分 |
| `test(web): end-to-end file workflows` | 文件工作流的端到端测试 |
| `fix(web): keep phone action bars above the tab bar and style name fields` | 截图检查中发现的两处布局问题 |

验证结果。Swift 测试 175 个、前端单元测试 108 个、端到端测试 19 个全部通过，端到端测试期间没有脚本错误、控制台错误或 CSP 拦截。替代验证环境中，App 改动后的 `VisionService` 与 `DuplicationDetectorService`、服务端的 `AppleImageProcessor` 都对照桩代码通过了类型检查，同一套桩代码也能编译改动前的 App 代码；共享核心的取色规则与原实现在 3,000 组样本上逐项一致，在 500 组有并列的样本上，核心的结果都在原实现所有可能的结果之中；相似分组在 2,000 组样本上一致。平局用例的比较方式最初有缺陷：每次调用原实现都会新建字典，遍历顺序不固定，所以「按排列重排」并没有覆盖全部顺序。修正为先排成固定顺序再重排后，连续 61 次运行全部通过，被测代码没有改动。备份导出与样例文件逐字段一致，导出后重新导入得到相同的数据。

遗留问题如下。

| 问题 | 说明 |
|---|---|
| macOS 上的图片处理未经编译 | 见 R6。需要在 Mac 上运行 `swift build` 与 `swift test`，并用真实照片走一遍单件录入、批量录入与相似检测 |
| 原图元数据 | 等待决策 D4。目前与 App 相同，原图连同 EXIF 等元数据原样保存，并随备份导出 |
| 备份格式没有槽位 | 第 1 版备份没有槽位字段，Web 版记录的穿搭槽位导出后会丢失。审计 Phase 1.4 的备份第 2 版可以解决 |
| 备份整份读入内存 | 导入上限 1 GB，与 App 和命令行相同，整份解析 |
| 看板中并列项的顺序不固定 | 件数相同的颜色在每次请求中的先后顺序可能不同，原因是共享统计规则按字典顺序处理并列，App 也是如此。属于行为修复轨道，见 R2 |
| 一次未能复现的测试失败 | `APITests.testUnknownImageDataIsServedAsAttachment` 在一次完整运行中失败，之后连续 33 次完整运行都通过。断言已改为在失败时输出响应内容，便于下次定位 |
| 相似检测每次全量计算 | 与 App 相同，不缓存特征，也不区分分类。对应审计 M-10，保持现状 |
| 缩略图首次生成 | macOS 上缩略图在第一次请求时生成并缓存，衣橱第一次打开会慢一些 |

### 第六阶段 Testing

本阶段对照审计报告 Phase 5 的测试分层检查现有测试，补上系统性的缺口，没有改动产品代码。

| 层次 | 覆盖内容 | 位置与数量 |
|---|---|---|
| 领域 | 枚举原始值契约、分类与保暖规则、生成引擎在固定随机源下的结果、统计、状态流转、筛选、差旅、取色与相似分组、备份格式契约 | `Tests/ClosetCoreTests`，66 个 |
| 数据库 | 迁移、取值列表与核心枚举一致、约束、至多一条活动记录、升级前备份、从版本 1 的数据库文件升级、上传宽限期、派生图生命周期 | `Tests/ClosetStorageTests`，30 个 |
| 应用服务 | 导入导出往返、导入前自动备份、单品新增与编辑、图片上传校验与处理、穿着流转、穿搭、看板、设置 | `Tests/ClosetServicesTests`，50 个 |
| API 与安全 | 每个端点的集成测试；每个写路由都要求来源校验、每个路由都拒绝外部 Host；非法枚举、格式错误的 id 与哈希、超大上传、SVG 上传、路径穿越；内部错误不暴露本机路径；缓存策略 | `Tests/ClosetHTTPTests`，34 个 |
| 前端单元 | 各页面与 App 的规则对照、请求内容、图片录入、备份对话框 | `Web/src/**/*.test.ts(x)`，108 个 |
| 端到端 | 在真实服务上走完整流程：脱下、洗衣、差旅、编辑、生成与穿着、手动拼搭、看板与日历、筛选、设置、删除、单件与批量录入、备份导出与导入；手机宽度下各页面不横向滚动 | `Web/e2e`，21 个 |
| 图像 | macOS 上抠图与取色对固定图片的回归 | 未完成，需要在 Mac 上进行，见 R6 |

新增的提交如下。

| 提交 | 内容 |
|---|---|
| `test(server): security checks across every API route` | 按路由逐一检查来源校验、Host 校验、参数格式与错误信息 |
| `test(web): phone layout checks` | 390 像素宽度下逐页检查横向滚动与底部标签栏 |

验证结果。Swift 测试 180 个、前端单元测试 108 个、端到端测试 21 个全部通过。

全部测试的运行方式如下。CI 中的五个任务分别执行这些命令，macOS 任务还会编译只在 macOS 上启用的图像代码。

```bash
swift test                       # 共享核心、存储、服务、HTTP
cd Web && npm run typecheck && npm test && npm run build
cd Web && npm run e2e            # 需要能运行 closet-server
```

遗留问题如下。图像层的回归测试需要 Mac 与一批真实衣物照片。替代验证环境中用来比较重构前后 App 行为的等价性测试与桩代码没有放入仓库，它们依赖重构前的代码快照，只用于当时的验证。

### 第七阶段 Local deployment

按决策 D6 先实现终端命令。审计 Phase 6 要求的「一条命令启动并打开浏览器、首次启动创建数据目录并选择空闲端口、升级前自动备份」均已具备，其中升级前备份在第二阶段已经实现。

| 提交 | 内容 |
|---|---|
| `feat(server): friendlier local start` | 自动查找前端构建产物；未指定端口时从 8765 起找空闲端口，指定的端口被占用则报错；`--open` 在服务开始监听后打开浏览器，只调用固定路径的系统命令；提示与错误立即输出 |
| `feat: one-command local start with scripts/closet` | 启动脚本：前端源文件有更新时才重新构建，增量构建 release 版服务端，然后启动并打开浏览器；`scripts/closet import` 导入备份 |
| `docs: local web guide and stage 7 record` | 使用指南 `docs/LOCAL_WEB.zh-CN.md` 与两份 README 的入口 |

验证结果。Swift 测试 185 个、前端单元测试 108 个、端到端测试 21 个全部通过。在本环境中实际运行了启动脚本：前端源文件更新后会重新构建，没有更新时跳过；通过 Swift 容器构建的 release 版服务端路径解析正确，并完成了一次导入，覆盖导入前自动保存了当前数据。服务端实际启动时，第二个实例自动改用 8766 并给出提示；指定被占用的端口或不存在的前端目录时输出一行错误并以状态码 1 退出。

遗留问题如下。脚本在 macOS 上尚未实际运行过，本环境只有 Linux，Mac 上的验证见 R1 与 R6。本环境的容器中没有 `xdg-open`，打开浏览器的分支只验证了失败时的提示。登录后自动运行等其它启动形态仍待决策 D6。

### 第八阶段 Final cleanup

| 提交 | 内容 |
|---|---|
| `chore: replace the migration placeholder and update moved-file notes` | 未知地址改为显示「页面不存在」，删除迁移期间的占位页；开发文档补充 Imaging 目录的说明 |
| `docs: final status, open decisions and Mac checklist` | 本节与第 8 章 |

最终验证结果。Swift 测试 185 个、前端单元测试 109 个、端到端测试 21 个全部通过。替代验证环境中，App 形态的等价性检查全部通过，其中生成器在 19,200 次调用下与重构前逐项一致；App 与服务端的图像代码对照桩代码通过类型检查。

## 8. 结果与后续

App 的全部页面都已可以在浏览器中使用：衣橱、单品详情与编辑、单件与批量录入、洗衣房、穿搭三个子页、日历、看板、高级筛选、差旅打包、设置、数据冷备份、清理相似衣物。业务规则只有一份，App 与 Web 版编译同一批源文件。数据含义不变，与 App 的有意差异全部列在第 4 章 R4 下的表格中。

### 需要你决定的问题

| 编号 | 问题 | 影响 |
|---|---|---|
| D4 | 原图元数据如何处理 | 目前与 App 相同，原图连同 EXIF 等元数据原样保存并随备份导出 |
| D5 | 未勾选场景的单品如何处理 | 目前与 App 相同，这类单品不参与穿搭生成与差旅打包 |
| D6 | 除终端命令外是否需要其它启动形态 | 例如登录后自动运行 |
| D2 | 是否需要手机通过局域网访问 | 需要时要先设计登录或配对，目前只监听本机 |

### 在 Mac 上需要完成的验证

本环境只有 Linux，下列项目没有在 Apple 工具链上执行过，见 R1 与 R6。CI 中已有对应任务，推送恢复后会自动运行前三项。

1. 用 Xcode 构建 iOS App，确认移动到 `Core` 与 `Imaging` 的文件以及 App 侧的改动能通过编译。
2. 在 Mac 上运行 `swift build` 与 `swift test`，确认 `ClosetImaging` 与 `AppleImageProcessor` 能通过编译。
3. CI 的 iOS 构建、Linux 与 macOS 的 Swift 测试、前端测试、端到端测试全部通过。
4. 用 `scripts/closet` 启动，从 App 导出一份真实备份并导入，核对单品数量、图片与穿着记录。
5. 用几张真实衣物照片走一遍单件录入与批量录入，确认抠图、取色、HEIC 显示与缩略图正常；运行一次相似检测。
6. 把 Web 版导出的备份导入 App，确认 App 能读取。

### 行为修复轨道

以下问题在迁移中保持了 App 的现状，并由特征测试固定，修复时测试会显式改变断言。修复放在共享核心中，App 与 Web 版同时生效：H-01（依赖 D5）、H-02、M-01、M-04、M-07、M-10、M-16、M-17，以及看板中并列项顺序不固定的问题。H-03 已修复，见第 9 章。

### 推送状态

迁移期间向 GitHub 推送时曾返回 403。写入权限修复后，全部提交已原样推送到 `claude/pensive-maxwell-sxj261`，基于 `origin/main` 的 `1ba1e0a`。

## 9. 稳定化修复

本阶段只处理审计报告中 Critical、High 与 P0 级别、并且有明确代码证据的问题。审计报告原文保存在 `docs/AUDIT_REPORT.zh-CN.md`。

### 已修复

| 编号 | 修复内容 | 位置 |
|---|---|---|
| H-03 | 穿收藏前检查每件单品都在衣橱中，并且上装、下装、鞋子齐全，不满足时给出提示并且不新建穿着记录。脱下时只处理当前在衣橱中的单品，在洗衣袋或行李箱中的单品状态与入袋时间保持不变。规则在共享核心 `ItemLifecycle.checkWear` 与 `ItemLifecycle.takeOff` 中，App 的收藏页、`WearService` 与服务端 `LifecycleService` 都调用它。完整性判断与 App 已有的 `Outfit.missingRequiredSlots` 相同 | `Core/Rules/ItemLifecycle.swift`、`Services/WearService.swift`、`Views/Outfit/FavoritesView.swift`、`Server/Sources/ClosetServices/LifecycleService.swift` |
| C-01 的版本校验部分 | 导入备份前检查 `version`，不是当前版本时明确拒绝，现有数据不被改动。服务端导入器此前已经校验版本 | `Core/Backup/WardrobeBackup.swift`、`Services/BackupService.swift` |
| P0-1 的 H-03 部分 | 状态流转规则在第一阶段已收敛到 `ItemLifecycle`，本阶段补上穿着前检查与脱下时的状态保护 | 同 H-03 |

行为变化如下。服务端 `POST /api/v1/wear-records` 与 `POST /api/v1/outfits/{id}/wear` 在单品不在衣橱时返回 409，消息中列出每件单品及其所在位置；穿已保存的穿搭缺少必选分类时同样返回 409。Web 收藏页已有的错误提示会直接显示这条消息。App 的生成页与自由拼搭只提供在衣橱中的单品，结果与服务端一致。原有的特征测试 `testTakeOffReturnsUncheckedLuggageItemToWardrobe_AuditH03` 固定的是缺陷行为，本次按修复后的行为改写，这是修复本身的目的，不是为了让测试通过。

### 暂缓

以下各项记为 `Deferred — requires architecture decision`。

| 编号 | 原因 |
|---|---|
| C-01 的流式与后台导出导入、P0-3 备份格式 v2 | 需要 `ModelActor` 重构与 zip 打包，iOS 系统框架是否满足 zip 打包在实现前需要确认，并且只能在 Apple 工具链上验证 |
| H-01、P0-2 | 依赖 D5 |
| H-02 | 下装、鞋子、袜子、配饰的天气规则需要产品决策 |
| H-04、P0-4 | 属于 iOS 渲染与查询性能。Web 端缩略图已在第五阶段完成 |
| H-05、P0-5 | `VersionedSchema` 与恢复界面涉及现有用户数据，需要在 Apple 工具链和真机上验证 |
| H-06 | 属于 iOS 并发重构，本环境无法验证 |
| P0-1 的 M-01、M-13 部分 | 属于 Medium 级别，不在本阶段范围内 |

C-02 与 P0-6 已在迁移中完成，见第六阶段。

### 验证

Swift 测试 192 个全部通过，新增测试覆盖共享规则、服务层与 HTTP 层。前端单元测试 109 个、端到端测试 21 个全部通过。替代验证环境中，App 形态的等价性检查全部通过，并新增了收藏穿着检查与 App 导入拒绝未知版本的检查。

在 Mac 上还需要确认两点。用 Xcode 构建 App，确认 `FavoritesView` 与 `WearService` 的改动能通过编译。在 App 中穿一套含有洗衣袋单品的收藏，确认出现提示并且没有新建穿着记录。
