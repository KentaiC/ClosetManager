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
| D6 | 启动方式 | 终端命令是任何形态都需要的最小形态 | 先实现终端命令；其它形态待决定 |
| D7 | 服务端持久化使用 SQLite 显式 schema，不复用 SwiftData | SwiftData 无法在 Linux 上编译测试；它没有 CHECK、外键、部分唯一索引这类约束，也没有可审查的迁移脚本（审计 H-05）。SwiftData 本身就以 SQLite 为底层存储，这里只是改为直接使用，不属于更换技术栈 | 已采用 |
| D8 | 服务端导入比 App 更严格 | App 遇到无法识别的取值会静默替换为默认值（审计 M-02），这会改变数据含义。服务端改为报错并拒绝导入；能在不改变含义的前提下处理的问题记为警告 | 已采用 |

## 3. 共享核心的组织方式

`ClosetManager/Core` 位于 iOS 工程的文件系统同步分组内，Xcode 把其中的文件编译进 App 模块；根目录 `Package.swift` 的 `ClosetCore` 目标以同一路径把它们编译成独立模块，供服务端使用。

选择这种方式的原因有两个。

第一，不需要修改 `project.pbxproj`。开发文档要求本地对该文件执行 `git update-index --skip-worktree`，对它的任何上游改动都会给本地拉取带来冲突。

第二，持久化类型留在 App 模块内。`Category`、`StoredColor` 等类型被 SwiftData 模型直接使用。若把它们移到另一个模块，类型的模块归属会改变，SwiftData 对此的处理方式 Repository 中没有足够信息确认，存在已有数据无法读取的风险。当前方式下类型名、模块、原始值都不变。

Core 只允许依赖 Foundation。SwiftUI 桥接放在 App 内，例如 `ClosetManager/Models/Support/StoredColor+SwiftUI.swift`。

## 4. Roadmap 调整

| 编号 | 调整 | 原因 |
|---|---|---|
| R1 | Apple 工具链上的编译验证延后，改用 Linux 验证环境作为替代 | 本会话推送到 GitHub 时返回 403，CI 无法触发。替代验证把 Core 与剥离 SwiftData 宏的模型文件编进同一模块做类型检查，并把重构前后的算法放在同一随机序列下逐项比较 |
| R2 | 行为缺陷修复单独成轨，不混入迁移阶段 | 迁移要求保持现有功能与数据含义。审计报告中的 H-01、H-02、H-03、M-01、M-04、M-07、M-17 等问题保持现状，已有特征测试的会在修复时显式改变断言。修复放在共享核心中进行，App 与 Web 同时生效。例外见 R4 |
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
  ClosetStorage    SQLite 封装、迁移、存储 actor、按内容寻址的图片存储
  ClosetServices   应用服务：备份导入、查询、单品编辑、穿着流转、穿搭、看板与筛选、差旅、设置
  ClosetHTTP       Hummingbird 路由、API 模型、安全中间件
  ClosetServer     命令行入口 closet-server
```

依赖方向为 ClosetServer → ClosetHTTP → ClosetServices → ClosetStorage → ClosetCore。

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
  src/features    按页面划分的功能，与 App 的 Views 目录一一对应
  e2e             Playwright 端到端测试
```

前端不定义任何枚举的中文名称或业务阈值，全部来自 `/api/v1/meta`。界面偏好只保存在当前浏览器，键名沿用 App 的 `@AppStorage` 键，包括 `galleryItemSize`、`ui.accent`、`ui.appearance`、`ui.cornerRadius`。个人资料属于数据，保存在服务端。

写操作成功后调用 `useDataVersion().invalidate()`，所有依赖数据版本的页面重新加载。这对应 App 中 SwiftData 的 `@Query` 在数据变化后自动刷新。

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
