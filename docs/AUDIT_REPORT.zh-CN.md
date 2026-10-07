# Closet Manager 技术审查报告

审查对象为 `KentaiC/ClosetManager`，分支 `claude/pensive-maxwell-sxj261`，提交 `1ba1e0a34239c0e41c96d911306f755335483432`。本轮只读审查，没有修改 repository 中的任何文件。

---

## 0. 报告前置摘要

### 0.1 最严重的 10 个问题

| 排名 | 编号 | 问题 | 严重度 | 处理时机 |
|---|---|---|---|---|
| 1 | C-01 | 备份是唯一的数据出口，但整包在内存中构建、在主线程执行、导入时不检查版本 | Critical | Web 化之前 |
| 2 | C-02 | 没有任何自动化测试、没有 CI，穿搭生成使用 `shuffled()` 无法复现 | Critical | Web 化之前 |
| 3 | H-05 | `ModelContainer` 创建失败直接 `fatalError`，且没有 `VersionedSchema` 与 `SchemaMigrationPlan` | High | Web 化之前 |
| 4 | H-03 | 收藏夹「今天穿这套」不检查单品状态，脱下流程会把洗衣袋或行李箱里的单品改回衣橱 | High | Web 化之前 |
| 5 | H-01 | 未勾选场景的单品永远不参与智能生成与差旅建议，新录入单品默认场景为空，失败提示指向错误原因 | High | Web 化之前 |
| 6 | H-02 | 生成算法只对上装和外套做保暖约束，下装、鞋、袜、配饰不受天气约束 | High | Web 化之前 |
| 7 | H-04 | 网格和缩略图每次渲染都解码完整图片，没有缩略图，九个视图各自全量 `@Query` | High | Web 化过程中 |
| 8 | M-01 | 编辑表单可以直接改状态，绕过 `laundryEntryDate` 的维护 | Medium | Web 化之前 |
| 9 | M-02 | 备份导入缺少校验，合并会产生多条 `isActive`，未知枚举值被静默改写 | Medium | Web 化之前 |
| 10 | H-06 | 文件读取、备份导出与导入在主线程同步执行 | High | Web 化过程中 |

### 0.2 最值得增加的 10 个功能

| 排名 | 功能 | 优先级 | 依据 |
|---|---|---|---|
| 1 | 统一的单品状态流转入口，含手动放入洗衣袋 | P0 | H-03、M-01 |
| 2 | 场景缺省策略，生成失败时说明真实原因 | P0 | H-01 |
| 3 | 备份格式 v2，含导入预检与导入前自动快照 | P0 | C-01、M-02 |
| 4 | 缩略图与图片规格化管线 | P0 | H-04，`docs/DEVELOPMENT.zh-CN.md:282` |
| 5 | 下装、鞋、袜、配饰的天气约束 | P1 | H-02 |
| 6 | 删除确认、软删除与撤销 | P1 | M-09 |
| 7 | 本地定时自动备份 | P1 | 当前只有手动冷备份 |
| 8 | 文本搜索，筛选结果可直接打开编辑 | P1 | M-17，`WardrobeSearchView.swift:45-49` |
| 9 | 单品穿着次数与最后穿着日期 | P1 | `WearRecord.swift:9` 注释中的后续规划 |
| 10 | 差旅期间可用行李箱单品生成穿搭，结束差旅时可选择入洗衣袋 | P2 | M-12 |

### 0.3 Local Web Migration 推荐架构

推荐采用 Option C 单进程本地 Web 应用，进程内部保持 Option B 式的 API 边界。浏览器只与本机 `127.0.0.1` 上的一个服务进程通信，这个进程同时提供静态前端、JSON API 和图片处理后台任务，数据保存在本机一个 SQLite 文件和一个媒体目录中。

```text
Browser  单页应用，TypeScript，所有静态资源随应用打包，不走 CDN
   │  HTTP JSON 与 multipart 上传，仅监听 127.0.0.1
   ▼
Local Server 单进程
   ├─ HTTP 层       路由、请求校验、Host 与 Origin 校验、错误映射、静态资源
   ├─ 应用服务层     单品、状态流转、穿搭、差旅、看板、备份、媒体
   ├─ 领域核心       生成算法、颜色归类与命名、保暖档位、差旅规则、统计
   ├─ 任务队列       抠图、取色、缩略图、相似度特征、备份导出与导入
   ├─ 仓储层         SQLite，WAL 模式，版本化迁移
   └─ 媒体存储       data/media/{original,processed,thumb}，文件名由服务端生成
```

后端语言取决于一个必须由你决定的问题。现有抠图和相似检测依赖 Apple Vision，只能在 Apple 平台运行。若 Web 版只需在 macOS 上运行，推荐 Swift 服务端，直接复用 `VisionService`、`DuplicationDetectorService` 和纯逻辑代码。若需要在 Windows 或 Linux 上运行，推荐 Python 服务端，抠图与相似检测改用本地 ONNX 模型，纯逻辑按黄金样本移植。第 6.3 节给出两条分支的完整对比，第 11.1 节列出待决问题。

### 0.4 问题处理时机总表

| 时机 | 问题编号 |
|---|---|
| 必须在 Web 化之前解决 | C-01、C-02、H-01、H-02、H-03、H-05、M-01、M-02、M-03、M-04、M-05、M-07、M-15 |
| 在 Web 化过程中解决 | H-04、H-06、M-06、M-08、M-09、M-10、M-11、M-13、M-14、M-18、M-19、L-05，以及第 8.4 节全部 Web 安全项 |
| 可以留到 Web 化之后 | M-12、M-16、M-17、L-01、L-02、L-03、L-04、L-06、L-07、L-08、L-09、L-10、L-11 |

划分原则如下。凡是影响导出数据正确性、或者决定移植后行为基准的问题，必须先在 iOS 版修正并用测试固定，否则移植时无法判断哪个行为才是正确的。凡是 Web 架构天然要重新实现的部分，例如图片管线、后台任务、上传校验，放在 Web 化过程中按新设计实现。体验改进和低风险问题放在之后。

---

## 1. Executive Summary

Closet Manager 是一个 iOS 17 及以上的 SwiftUI 应用，持久化使用 SwiftData，智能能力来自 Vision、CoreImage 和 Swift Charts，项目文档把纯本地离线定为硬性原则，见 `docs/DEVELOPMENT.zh-CN.md:26`。仓库共 62 个文件，其中 53 个 Swift 文件合计 5,120 行，视图层 2,844 行，模型层 1,109 行，服务层 893 行，ViewModel 204 行。提交历史共 8 次，时间为 2026-06-20 到 2026-07-12。

功能覆盖面已经比较完整，单品录入、批量录入、叠穿生成、洗衣流转、差旅打包、看板、相似检测、备份都有实现。主要风险集中在四处。状态机没有唯一入口，多个界面路径可以绕过不变量。生成算法的天气约束只覆盖躯干。数据出口只有一个整包 JSON 备份，而且大数据量下不可靠。项目没有任何测试和 CI，最近一次提交 `1ba1e0a` 的标题是 `Fix build: import SwiftUI in ImageSource (#1)`，说明主分支曾经处于无法编译的状态。

架构上，目录按 Models、Services、ViewModels、Views 分层，但 SwiftData 的 `@Model` 类型贯穿所有服务，视图里还承载了不少业务规则，`Models/ImageSource.swift` 直接依赖 PhotosUI。核心算法本身体量小、无副作用，移植成本低。整套 UI 和 Apple 专属框架无法进入浏览器。

距离 Local Web Application 的结论是 UI 需要全部重写，持久化需要重建，图片智能处理需要按平台决策复用或替换，领域逻辑可以复用或低成本移植。`.wardrobe` 备份格式是把 iPhone 上现有数据迁到 Web 版的唯一现成通道，所以 C-01 和 M-02 必须最先处理。

### 1.1 审查方法与限制

本轮逐个读取了全部 53 个 Swift 文件、`project.pbxproj`、asset catalog、`.gitignore`、`README.md`、`README.zh-CN.md`、`docs/DEVELOPMENT.zh-CN.md`，并检查了完整 git 历史与模型文件的历次差异。用 grep 核对了每个符号的引用情况。颜色归类与命名的结论，是在 scratchpad 中按 `StoredColor.hsb` 与 `ColorCategory.classify` 的公式逐项重算得到的。

以下内容在仓库中不存在，已逐一确认。没有 `CLAUDE.md`，没有 `.claude/` 目录，没有测试目标和测试文件，没有 `#Preview`，没有 CI 配置，没有 lint 配置，没有 sample data 或 fixtures，没有共享 scheme，没有 entitlements，没有手写 Info.plist，工程使用 `GENERATE_INFOPLIST_FILE = YES`。项目中不存在 PDF 处理，也不存在 API、CLI、网络请求、子进程调用。

本容器是 Linux，没有 `swift`、`xcodebuild` 和 iOS SDK，代理对 `download.swift.org` 返回 403，因此无法执行 build、type check 或运行应用。项目已经可以运行这一点，Repository 中没有足够信息确认这一点。仓库里也没有可执行的测试。

---

## 2. Architecture Review

### 2.1 Application architecture

| 关注点 | 实际位置 |
|---|---|
| UI | `ClosetManager/Views/` 全部 SwiftUI 视图，入口为 `App/ClosetManagerApp.swift` 中的 `ContentView`，五个 Tab 依次为衣橱、洗衣房、穿搭、日历、看板 |
| Business logic | `Services/` 下的 `OutfitGeneratorService`、`WearService`、`TravelService`、`AnalyticsService`、`BackupService`；`ViewModels/ItemDraftModel.swift`；另有一部分规则写在视图中，见 M-18 |
| Data access | 视图通过 `@Query` 直接读取，通过 `@Environment(\.modelContext)` 直接写入；服务以参数形式接收 `ModelContext` |
| File processing | `Services/VisionService.swift` 负责抠图与取色，`Services/DuplicationDetectorService.swift` 负责特征指纹，`Services/BackupService.swift` 负责备份文件读写，`WardrobeGalleryView` 与 `ItemFormSections` 自行读取导入文件 |
| Database | SwiftData，`Models/ClosetSchema.swift` 注册 `ClothingItem`、`Outfit`、`WearRecord` 三个模型，使用默认 `ModelConfiguration` |
| Configuration | 构建配置在 `project.pbxproj`；运行时偏好全部是 `@AppStorage`，键名为 `ui.accent`、`ui.appearance`、`ui.cornerRadius`、`galleryItemSize`、`profile.heightCm`、`profile.weightKg`、`profile.age`、`profile.gender` |
| Background processing | 没有后台任务调度。耗时图像处理放在两个 `actor` 中执行，`VisionService.shared` 与 `DuplicationDetectorService.shared` |
| External dependencies | 只有 Apple 系统框架，SwiftUI、SwiftData、Vision、CoreImage、CoreGraphics、ImageIO、UniformTypeIdentifiers、PhotosUI、Charts。没有第三方包，`packageProductDependencies` 为空 |

模块调用关系如下。

```text
ContentView TabView
 ├─ WardrobeGalleryView ── ItemEditorView ─┐
 │    ├─ BatchImportView ──────────────────┼─ ItemFormSections ─ ItemDraftModel ─ VisionService.shared
 │    ├─ SettingsView ─ TravelCapsuleView ─┼─ OutfitGeneratorService
 │    │               ├─ DuplicationView ── DuplicationDetectorService.shared
 │    │               └─ BackupService
 │    ├─ WardrobeSearchView
 │    └─ ActiveOutfitWidget ─ TakeOffSheet ─ WearService
 ├─ LaundryView ─ WearService
 ├─ OutfitHomeView
 │    ├─ OutfitGeneratorView ─ OutfitGeneratorService, WearService
 │    ├─ FavoritesView ─ WearService
 │    └─ ManualOutfitBuilderView ─ WearService
 ├─ CalendarHistoryView
 └─ AnalyticsDashboardView ─ AnalyticsService
所有视图与服务 ─ SwiftData ModelContext 与 @Model 类型
```

没有发现循环依赖。依赖方向是视图到服务再到模型，但服务的入参和出参都是 SwiftData 的 `@Model` 类，这让服务层与持久化框架绑定在一起。

### 2.2 Data flow

单件录入。用户在 `WardrobeGalleryView` 选择单件录入，打开 `ItemEditorView`。在 `ItemFormSections` 中通过 PhotosPicker 或 `.fileImporter` 选图，触发 `ItemDraftModel.process`。`ingest` 先把原始数据写入 `originalImageData`，再调用 `VisionService.removeBackground`，内部流程为 `CGImageSource` 解码、读取 EXIF 方向、`VNGenerateForegroundInstanceMaskRequest`、`generateMaskedImage`、`CIContext` 渲染、编码为带透明通道的 PNG。随后 `extractColors` 把图缩放到 48×48，按 6×6×6 量化求主色与辅色。用户编辑字段后点保存，`makeNewItem` 生成 `ClothingItem`，`modelContext.insert` 写入上下文，由 SwiftData autosave 落盘，图片走 `.externalStorage`。所有带 `@Query` 的视图随之刷新。

```text
User → ItemFormSections → ItemDraftModel.process → VisionService.removeBackground
     → VisionService.extractColors → 表单显示 → 保存 → modelContext.insert → autosave
     → SQLite 与外部存储文件 → @Query 刷新
```

批量录入。入口有三个，相册多选上限 30 张，文件多选不限数量，拖拽释放不限数量。三者都转换成 `[ImageSource]` 交给 `BatchImportView`，它通过 `.task(id: index)` 为每张图新建一个 `ItemDraftModel` 并处理，用户逐张保存或跳过。

穿搭生成。`OutfitGeneratorView` 读取全部单品，在主线程同步调用 `OutfitGeneratorService.generate`，结果 `[OutfitDraft]` 存在视图 `@State` 中。收藏调用 `WearService.addToFavorites` 插入 `Outfit`，今天穿调用 `WearService.wearToday`，先把所有活动记录置为非活动，再插入一条 `isActive == true` 的 `WearRecord`。

脱下与洗衣。`ActiveOutfitWidget` 用 `#Predicate { $0.isActive }` 找到活动记录，`TakeOffSheet` 按分类给出默认勾选，`WearService.takeOff` 把勾选的单品改为 `inLaundry` 并写入入袋时间，其余单品改为 `inWardrobe`。`LaundryView` 读取全部单品后在内存中筛出 `inLaundry`，`returnToWardrobe` 把选中单品放回。

差旅。`TravelCapsuleView` 以 `maxCount: days` 调用生成算法，合并去重后得到建议清单，`packIntoLuggage` 改为 `inLuggage`，`unpackAllLuggage` 把所有 `inLuggage` 改回 `inWardrobe`。

看板。`AnalyticsDashboardView` 读取全部单品和全部记录，调用 `AnalyticsService` 的四个函数，渲染条形图、颜色树形图、色彩偏好和 16 周热力图。

相似检测。`DuplicationView` 进入时在主线程准备 `ItemFingerprintInput` 数组，交给 actor 逐张计算 `VNFeaturePrintObservation`，两两比较后用并查集分组，再映射回 `ClothingItem`。

备份。导出时 `BackupService.exportFile` 在主线程取出全部数据，图片转 base64 内联，整体编码成一个 JSON `Data`，写入临时目录，由 `ShareLink` 分享。导入时 `.fileImporter` 接受任意数据文件，用户选择覆盖或合并，`restore` 读取整个文件、解码、按 id 重建关系。

### 2.3 Storage

| 项目 | 现状 |
|---|---|
| 数据库 | SwiftData，底层存储格式由框架管理，`ClosetSchema.makeContainer` 使用默认位置 |
| Schema | `ClothingItem`、`Outfit`、`WearRecord` 三个实体。`ClothingItem` 与 `Outfit` 多对多，`ClothingItem` 与 `WearRecord` 多对多，`Outfit` 与 `WearRecord` 一对多。删除规则全部为 `.nullify`。三者的 `id` 都标记 `@Attribute(.unique)` |
| 枚举存储 | `scenarios`、`warmthLevels`、`seasons` 是 Codable 枚举数组，`category`、`status`、`subtype` 是 Codable 枚举，`dominantColor` 与 `secondaryColor` 是复合属性 `StoredColor` |
| Migrations | 没有 `VersionedSchema`，没有 `SchemaMigrationPlan`。文档第 9 节说明完全依赖新增带默认值字段的轻量迁移 |
| 导入文件 | 原始字节原样存入 `originalImageData`，不缩放，不转码，不剥离元数据 |
| 生成文件 | 抠图结果为 PNG，存入 `processedImageData`；备份文件写入 `FileManager.default.temporaryDirectory`，文件名 `ClosetBackup-<时间戳>.wardrobe` |
| 临时文件 | 导出文件写入后没有删除逻辑 |
| Backup / restore | 仅手动，整包 JSON，覆盖或合并两种模式；没有自动备份，没有导入前快照，`@AppStorage` 中的画像和外观设置不在备份内 |
| 数据一致性 | 至多一条 `isActive` 记录只靠 `WearService.deactivateActiveRecords` 维护；`laundryEntryDate` 与状态的对应只靠 `takeOff` 和 `returnToWardrobe` 维护；子类与分类的匹配只靠表单中的 `reconcileSubtype` 维护。数据库层没有任何约束保证这些规则 |
| 保存时机 | 全仓库没有任何 `save()` 调用，完全依赖 SwiftData autosave |

### 2.4 Existing interfaces

| 接口类型 | 是否存在 | 说明 |
|---|---|---|
| HTTP API | 否 | 无网络代码 |
| Services | 是 | 五个无状态 `enum` 服务和两个 `actor` 服务 |
| Controllers / routes | 否 | 导航由 `TabView`、`.sheet`、`NavigationLink` 完成，`EditorRoute` 是唯一的路由枚举 |
| 可复用业务逻辑 | 部分 | 生成算法、颜色、保暖、差旅、统计是纯逻辑，但入参是 `@Model` 类 |
| CLI | 否 | |
| 平台专属代码 | 全部 | 整个应用是 iOS 应用，图片处理依赖 Apple 框架 |
| UI 内嵌逻辑 | 是 | 见 M-18 |
| 强耦合组件 | 是 | 服务依赖 `ModelContext`；`ItemDraftModel` 直接调用 `VisionService.shared`；`ImageSource` 在模型层引用 `PhotosPickerItem` |

可以复用于 Web 版的代码按复用方式分为三类。

| 代码 | 行数 | Swift 服务端分支 | 跨平台分支 |
|---|---|---|---|
| `OutfitGeneratorService.swift` | 171 | 解耦 `@Model` 后直接复用 | 按黄金样本移植 |
| `TravelService.swift` | 24 | 直接复用 | 移植 |
| `AnalyticsService.swift` | 49 | 解耦后复用 | 移植 |
| `Models/Enums/*` 中的领域枚举 | 约 700 | 直接复用 | 原始值必须逐字保留 |
| `ColorCategory.classify`、`ColorNaming`、`StoredColor.hsb` | 约 190 | 直接复用 | 移植并用表驱动测试校验 |
| `VisionService.swift` | 204 | macOS 14 及以上可复用 | 不可用，需要替换模型 |
| `DuplicationDetectorService.swift` | 102 | macOS 14 及以上可复用，阈值沿用 | 不可用，阈值需重新标定 |
| `BackupService.swift` 中的 DTO | 约 50 | 作为导入契约复用 | 作为导入契约复用 |
| `WearService.swift` | 129 | 规则复用，实现改为事务 | 规则移植 |
| `ItemDraftModel.swift` | 204 | 命名与季节推导规则可复用 | 规则移植 |
| `Views/*` | 2,844 | 不可复用 | 不可复用 |

Web 导入器必须逐字使用的枚举原始值如下，全部取自源码。

| 枚举 | 原始值 |
|---|---|
| `Category` | `outerwear` `top` `bottom` `shoes` `accessory` `socks` |
| `ItemStatus` | `inWardrobe` `inLaundry` `inLuggage` |
| `Scenario` | `work` `casual` `sport` `formal` |
| `WarmthLevel` | `frigid` `cold` `cool` `mild` `warm` `hot` |
| `Season` | `spring` `summer` `autumn` `winter` |
| `OutfitSource` | `generated` `manual` |
| `Subtype` | `jacket` `trenchCoat` `overcoat` `downJacket` `paddedJacket` `leatherJacket` `blazer` `cardigan` `vest` `tee` `polo` `shirt` `hoodie` `sweater` `tankTop` `baseLayer` `suit` `jeans` `casualPants` `dressPants` `sweatpants` `shorts` `skirt` `sneakers` `canvasShoes` `leatherShoes` `boots` `sandals` `slippers` `heels` `hat` `scarf` `belt` `bag` `gloves` `glasses` `tie` `jewelry` `noShowSocks` `ankleSocks` `crewSocks` `kneeSocks` `athleticSocks` |
| `ColorCategory` | `black` `white` `gray` `beige` `brown` `red` `orange` `yellow` `green` `cyan` `blue` `purple` `pink` `multicolor` |

`.wardrobe` v1 的键名取自 `BackupService.swift:17-66`。顶层为 `version`、`items`、`outfits`、`wearRecords`。单品为 `id`、`name`、`category`、`subtype`、`scenarios`、`status`、`isWaterproof`、`laundryEntryDate`、`dominantColor`、`secondaryColor`、`warmthScore`、`warmthLevels`、`seasons`、`brand`、`notes`、`createdAt`、`updatedAt`、`processedImageBase64`、`originalImageBase64`。颜色对象为 `red`、`green`、`blue`、`alpha`。穿搭为 `id`、`name`、`isFavorite`、`source`、`targetScenario`、`targetWarmthLevel`、`itemIDs`、`createdAt`、`updatedAt`。穿着记录为 `id`、`date`、`isActive`、`outfitID`、`itemIDs`、`notes`、`createdAt`。日期编码策略为 `.iso8601`。`dominantColorCategory` 不在备份中，导入时由 `ClothingItem.init` 重新计算。`canvasLayoutData` 不在备份中，目前也没有任何代码写入这个字段。建议在动手写 Web 导入器之前，从真机导出一份真实文件作为 fixture，用它锁定字段缺省时的实际形态。

---

## 3. Bugs / Issues

每个问题包含位置、证据、问题、影响、建议修复。行号对应提交 `1ba1e0a`。

### 3.1 Critical

#### C-01 唯一的数据出口不可靠

| 项目 | 内容 |
|---|---|
| 位置 | `Services/BackupService.swift:71-130`，`:135-144`；`Views/SettingsView.swift:142-147`，`:173-182` |
| 证据 | `makeBundle` 一次取出全部记录，每个单品同时生成 `processedImageBase64` 与 `originalImageBase64`，见 `:93-94`。`exportFile` 把整个包编码为一个 `Data` 再写盘，见 `:122`、`:128`。`restore` 用 `Data(contentsOf:)` 读入整个文件，见 `:139`。两处调用都在按钮动作中同步执行，见 `SettingsView.swift:143`、`:176`。`Bundle.version` 固定为 1，`restore` 从不读取它 |
| 问题 | 导出峰值内存等于全部原图与抠图的 base64 文本加上 JSON 编码缓冲，原图没有任何缩放。导入同样整体驻留内存。版本字段只写不查 |
| 影响 | 备份是把 iPhone 数据迁到 Web 版的唯一现成通道。单品数量增加到一定规模后导出会失败或卡住主线程，迁移就被阻断。具体阈值与设备内存相关，Repository 中没有足够信息确认这一点。未来格式变化后，旧版应用会按新文件解码而不是明确拒绝 |
| 建议 | 短期把导出与导入移到 `ModelActor` 后台执行，逐条流式写出，导入时校验 `version`。中期定义 v2 格式，使用 zip 包含 `manifest.json` 与独立图片文件，并附带校验和，见第 9 节 P0-3 |

#### C-02 没有任何自动化测试与 CI，生成结果不可复现

| 项目 | 内容 |
|---|---|
| 位置 | `ClosetManager.xcodeproj/project.pbxproj:50-73`；`Services/OutfitGeneratorService.swift:54`、`:61`、`:63`、`:67`、`:68`、`:69` |
| 证据 | 工程只有一个 `PBXNativeTarget`，类型为 `com.apple.product-type.application`，没有测试目标。仓库中没有 XCTest 或 Swift Testing 文件，没有 CI 配置。生成算法对每个候选池调用 `.shuffled()`，使用系统随机源。`ClosetSchema.swift:7` 的注释提到单元测试用内存容器，但测试并不存在。提交 `1ba1e0a` 修复了一次已进入主分支的编译错误 |
| 问题 | 没有回归保护，没有编译门禁，核心算法输出每次不同，无法写确定性断言 |
| 影响 | Web 迁移需要证明移植后行为一致，目前没有任何可对照的基准。任何修复都无法确认没有破坏其它路径 |
| 建议 | 增加测试目标。给 `generate` 增加可注入的 `RandomNumberGenerator` 参数并保留默认值。为生成算法、颜色归类、保暖映射、差旅、统计、备份往返建立黄金样本，样本以 JSON 保存，供 Web 版复用 |

### 3.2 High

#### H-01 未勾选场景的单品不参与生成，提示指向错误原因

| 项目 | 内容 |
|---|---|
| 位置 | `ViewModels/ItemDraftModel.swift:25`；`Services/OutfitGeneratorService.swift:47-49`；`Views/Components/ItemFormSections.swift:221-235`；`Views/Outfit/OutfitGeneratorView.swift:117-124`；`Views/BatchImportView.swift:36-41` |
| 证据 | 草稿默认 `selectedScenarios` 为空集合。生成池的条件是 `$0.scenarios.contains(scenario)`。表单只对正式与运动的冲突给出提示，不要求至少选一个场景。批量录入每张图都新建草稿，场景重新为空。缺少必选项时提示文案为「请先在衣橱补充对应单品」 |
| 问题 | 用户不勾选场景就保存的单品，对任何场景都不可见，而界面告诉用户的是缺少单品 |
| 影响 | 批量录入是最常用的录入方式，批量录入的单品默认全部被智能生成和差旅建议排除，核心功能对新用户表现为失效 |
| 建议 | 选择一种明确策略并写入测试。保存时要求至少一个场景，或者把空场景视为适用全部场景。生成失败时按原因分别提示，例如有上装但都没有勾选该场景 |

#### H-02 天气约束只覆盖上装和外套

| 项目 | 内容 |
|---|---|
| 位置 | `Services/OutfitGeneratorService.swift:52-69` |
| 证据 | 上装与外套按 `warmthScore <= maxSingle` 过滤，见 `:53`、`:57`。下装 `:63`、配饰 `:68`、袜子 `:69` 没有任何保暖或季节条件，鞋子 `:65-67` 只排除拖鞋并在雨雪开关打开时要求防水。`seasons` 字段在生成算法中没有被读取，全仓库只在模型、草稿和备份中出现 |
| 问题 | 在严寒档位下，短裤、凉鞋、船袜可以与羽绒服组成同一套结果；在炎热档位下，围巾和手套可以被选为配饰 |
| 影响 | 生成结果与 README 描述的保暖度匹配气温不一致，用户对核心推荐失去信任 |
| 建议 | 为下装、鞋、袜、配饰引入基于 `warmthScore` 或 `seasons` 的过滤规则，规则用表驱动测试固定。规则确定后再移植到 Web 版 |

#### H-03 收藏夹穿着路径绕过单品状态

| 项目 | 内容 |
|---|---|
| 位置 | `Views/Outfit/FavoritesView.swift:70-73`；`Services/WearService.swift:54-64`；`Services/WearService.swift:81-97`；`Views/Outfit/TakeOffSheet.swift:16-20`、`:107-111` |
| 证据 | `wearOutfit` 直接使用 `outfit.items` 创建活动记录，不检查 `isAvailable`。`takeOff` 对未勾选的单品一律执行 `item.status = .inWardrobe` 与 `item.laundryEntryDate = nil`。脱下弹窗默认不勾选外套、鞋子、配饰 |
| 问题 | 收藏中含有一件在行李箱或洗衣袋中的外套，用户点今天穿这套，再按默认勾选脱下，这件外套的状态变为在衣橱，入袋时间被清空 |
| 影响 | 状态机数据被静默改写，洗衣房和差旅清单与实物不一致。删除单品后收藏会缺少必选槽位，`isStructurallyValid` 已存在但没有被调用，残缺的收藏仍可穿着 |
| 建议 | 穿着前校验每件单品状态和结构完整性，给出明确提示。`takeOff` 只处理当前状态为在衣橱的单品，对其它状态保持不变。状态改写全部收敛到一个流转服务，见 P0-1 |

#### H-04 图片渲染没有缩略图，查询全部在内存中进行

| 项目 | 内容 |
|---|---|
| 位置 | `Views/Components/ItemCard.swift:18-20`、`:47`；`Views/Components/ItemThumbnail.swift:8-10`、`:17`；`Support/PlatformImage.swift:13-16`；`docs/DEVELOPMENT.zh-CN.md:282` |
| 证据 | 每个卡片在 `body` 中通过 `Image(platformData:)` 从完整 `Data` 构造 `UIImage`。没有抠图结果时回退到 `originalImageData`，也就是未缩放的原图。文档已承认这一点。`@Query` 读取全部单品的视图有八个，分别是 `WardrobeGalleryView:11`、`LaundryView:9`、`OutfitGeneratorView:8`、`ManualOutfitBuilderView:10`、`AnalyticsDashboardView:10`、`TravelCapsuleView:8`、`WardrobeSearchView:8`、`DuplicationView:10`，另有 `CalendarHistoryView:10` 读取全部记录。按状态过滤全部在内存中完成，`LaundryView.swift:8` 的注释说明这是为了避开枚举谓词 |
| 问题 | 每次重绘都发生外部存储读取与整图解码。数据量增长后，滚动和切换 Tab 的开销随单品数线性上升 |
| 影响 | 大衣橱下滚动卡顿与内存压力。具体从多少件开始明显，Repository 中没有足够信息确认这一点 |
| 建议 | iOS 版可以先用内存缓存加降采样解码，不改 schema。Web 版在入库时生成缩略图，列表只请求缩略图，原图按需加载，见 P0-4 |

#### H-05 容器创建失败直接崩溃，没有迁移计划

| 项目 | 内容 |
|---|---|
| 位置 | `Models/ClosetSchema.swift:18-28`；`docs/DEVELOPMENT.zh-CN.md:251-255` |
| 证据 | `ModelContainer` 初始化失败时调用 `fatalError`。仓库中没有 `VersionedSchema` 和 `SchemaMigrationPlan`。git 历史显示模型已经演进多次，新增了 `subtype`、`isWaterproof`、`laundryEntryDate`、`warmthScore`、`isActive` 和 `ItemStatus.inLuggage` |
| 问题 | 一旦某次模型变更超出轻量迁移的能力，应用启动即终止，而备份导出入口在应用内部，用户无法自救 |
| 影响 | 数据整体不可访问。Phase 1 会引入模型调整，触发概率随之上升 |
| 建议 | 把当前模型声明为 `VersionedSchema` 的 V1，后续变更走显式迁移计划。容器创建失败时进入恢复界面，提供重试和导出原始存储文件的入口，而不是终止进程 |

#### H-06 文件读取和备份在主线程同步执行

| 项目 | 内容 |
|---|---|
| 位置 | `Views/WardrobeGalleryView.swift:134-144`；`Views/Components/ItemFormSections.swift:51-58`；`Views/SettingsView.swift:143`、`:176` |
| 证据 | 文件导入在回调中循环执行 `Data(contentsOf:)`。备份导出与导入在按钮动作中直接调用 |
| 问题 | 多选大文件或 iCloud Drive 文件时，读取期间界面无响应，读取失败被 `try?` 静默丢弃 |
| 影响 | 交互卡顿，失败无反馈 |
| 建议 | iOS 版移到后台任务并显示进度。Web 版统一走上传接口和后台任务队列 |

### 3.3 Medium

#### M-01 编辑表单可直接修改状态

| 项目 | 内容 |
|---|---|
| 位置 | `Views/Components/ItemFormSections.swift:299-317`；`ViewModels/ItemDraftModel.swift:193`；`Views/LaundryView.swift:100-103`；`Models/ClothingItem.swift:29` |
| 证据 | 表单提供三态分段选择器，`apply(to:)` 只写 `item.status`，不处理 `laundryEntryDate`。模型注释写明非洗衣袋状态时为 nil。滞留预警在入袋时间为 nil 时返回 false |
| 问题 | 通过编辑器放入洗衣袋的单品没有入袋时间，永远不会出现滞留预警；通过编辑器放回衣橱的单品保留旧的入袋时间 |
| 影响 | 状态与时间字段不一致。应用中除脱下流程外，没有其它手动放入洗衣袋的入口，用户只能走这条有缺陷的路径 |
| 建议 | 编辑器中的状态修改改为调用流转服务；在衣橱网格增加放入洗衣袋操作 |

#### M-02 备份导入缺少校验

| 项目 | 内容 |
|---|---|
| 位置 | `Services/BackupService.swift:162-212` |
| 证据 | 未知分类回退为 `.top`，见 `:166`；未知状态回退为 `.inWardrobe`，见 `:169`；未知来源回退为 `.generated`，见 `:191`。子类与分类分别解析，没有一致性检查。穿着记录直接使用 `dto.isActive`，见 `:206`。合并模式遇到已存在的 id 直接跳过，见 `:163`、`:188`、`:204`。`.fileImporter` 接受任意数据类型，见 `SettingsView.swift:47` |
| 问题 | 合并一个含活动记录的备份到一个已有活动记录的库，结果是两条 `isActive == true`。被篡改或版本不匹配的文件会被静默改写为看似合法的数据。合并只插入不更新 |
| 影响 | 违反至多一条活动记录的约定；数据被静默改写，用户没有任何提示 |
| 建议 | 导入前做预检，输出数量统计、未知值清单、关系缺失清单，用户确认后再写入。合并时把导入的活动记录全部置为非活动，或按时间只保留一条。枚举遇到未知值时报错而不是回退 |

#### M-03 覆盖导入的唯一约束行为没有验证

| 项目 | 内容 |
|---|---|
| 位置 | `Services/BackupService.swift:147-151`、`:162-184`；`Models/ClothingItem.swift:8` |
| 证据 | 覆盖模式先删除全部对象，再以备份中的相同 id 插入新对象，二者处于同一个未保存的上下文中，`id` 带有 `@Attribute(.unique)` |
| 问题 | 用同一份备份覆盖导入时，SwiftData 对同 id 先删后插的保存结果，Repository 中没有足够信息确认这一点，也没有任何测试覆盖 |
| 影响 | 这是迁移演练中最常见的操作路径，结果未经验证 |
| 建议 | 在内存容器上写一个导出后覆盖导入再导出的往返测试，断言两次导出内容一致 |

#### M-04 新单品在未拖动保暖滑条时季节为空

| 项目 | 内容 |
|---|---|
| 位置 | `ViewModels/ItemDraftModel.swift:28-29`、`:145-148`、`:161`、`:178`；`Views/Components/ItemFormSections.swift:34-36`；`Models/ClothingItem.swift:118` |
| 证据 | 草稿初始 `selectedSeasons` 为空。季节推导只在 `warmthScore` 发生变化时由 `.onChange` 触发，初始值不会触发。`makeNewItem` 传入非可选的空数组，`ClothingItem.init` 只在参数为 nil 时推导 |
| 问题 | 界面写着默认由保暖程度自动推导，实际保存的季节为空数组 |
| 影响 | 季节数据缺失进入备份，未来按季节筛选或生成时这些单品会被遗漏 |
| 建议 | 草稿初始化时执行一次推导，或在 `makeNewItem` 中对未手动编辑的空集合执行推导，并补测试 |

#### M-05 手动拼搭的收藏被记录为算法生成

| 项目 | 内容 |
|---|---|
| 位置 | `Services/WearService.swift:19-26`；`Views/Outfit/ManualOutfitBuilderView.swift:137-140`；`Models/Enums/OutfitSource.swift:8` |
| 证据 | `addToFavorites` 固定写入 `source: .generated`。全仓库没有任何地方写入 `.manual` |
| 问题 | `OutfitSource` 字段的值不可信 |
| 影响 | 迁移后的数据无法区分来源，按来源统计的结果错误 |
| 建议 | 给 `addToFavorites` 增加来源参数，由调用方传入 |

#### M-06 叠穿层次没有持久化

| 项目 | 内容 |
|---|---|
| 位置 | `Services/OutfitGeneratorService.swift:9-10`；`Services/WearService.swift:25`；`Models/Outfit.swift:39-40`、`:74-91` |
| 证据 | 草稿中的 `top` 与 `midLayer` 都是上装分类。收藏时只保存 `draft.allItems` 这一组单品。`Outfit` 没有记录槽位或顺序的字段，`top` 取第一件上装 |
| 问题 | 一套含打底和中层的收藏，持久化后无法区分哪件是打底。SwiftData 对多关系数组顺序的持久化行为，Repository 中没有足够信息确认这一点。`Outfit` 上的槽位访问器在全仓库没有被调用 |
| 影响 | Web 版若照搬现有模型，会继承这个信息丢失 |
| 建议 | Web 版的穿搭与单品关联表增加 `slot` 与 `position` 字段，见第 7.4 节 |

#### M-07 中层选择的回退分支选中最暖的一件

| 项目 | 内容 |
|---|---|
| 位置 | `Services/OutfitGeneratorService.swift:139-149` |
| 证据 | 中层集合按保暖度升序排列，`first(where:)` 找不到不超过预算加 25 的上装时，回退到 `.last`，也就是超出最多的那一件 |
| 问题 | 按代码逐步推演一个实例。档位暖和，预算 40，单件上限 58。上装为 T 恤 24、毛衣 45、卫衣 58。打底选 24，24 小于 25，进入中层选择。满足 24 加 w 不超过 65 的上装不存在，回退选中 58，躯干总和 82。若回退到 `.first`，选中 45，总和 69 |
| 影响 | 暖和天气下给出明显过厚的组合 |
| 建议 | 回退时选择超出最少的一件，或在超出过多时不加中层。修改前先用 C-02 的黄金样本固定当前行为 |

#### M-08 非图片数据可以被保存为单品

| 项目 | 内容 |
|---|---|
| 位置 | `Views/WardrobeGalleryView.swift:76-80`；`ViewModels/ItemDraftModel.swift:78`、`:115-127` |
| 证据 | 拖拽目标接受 `Data.self`。`ingest` 先把数据写入 `originalImageData`，解码失败后取色回退为灰色。`canSave` 只检查是否有数据且不在处理中 |
| 问题 | 解码失败的数据仍可保存，单品显示占位图标 |
| 影响 | 产生无效记录，Web 版若照搬会扩大为上传校验漏洞 |
| 建议 | 解码失败时禁止保存或要求更换图片。Web 版在服务端做类型嗅探和解码验证 |

#### M-09 删除没有确认也没有撤销

| 项目 | 内容 |
|---|---|
| 位置 | `Views/WardrobeGalleryView.swift:239-245`、`:267-269`；`Views/DuplicationView.swift:61-66`、`:101-107`；`Views/Outfit/FavoritesView.swift:27`、`:75-79`；`Views/CalendarHistoryView.swift:27`、`:60-64` |
| 证据 | 四处删除都直接调用 `modelContext.delete` |
| 问题 | 误触即永久删除，相似检测页的删除按钮与缩略图紧邻 |
| 影响 | 数据丢失，只能从手动备份恢复 |
| 建议 | 删除前确认；Web 版采用软删除，保留一段时间可撤销 |

#### M-10 相似检测跨分类比较且每次全量重算

| 项目 | 内容 |
|---|---|
| 位置 | `Services/DuplicationDetectorService.swift:16-20`、`:34-39`、`:53-67`；`Views/DuplicationView.swift:84-91` |
| 证据 | 输入结构只有 `id`、`imageData`、`color`，没有分类。每次运行都为全部单品重新计算特征指纹，然后两两比较。输入包含所有单品的完整图片数据，含洗衣袋和行李箱中的单品 |
| 问题 | 不同分类的单品会被分到同一组。计算量随单品数平方增长，结果不缓存 |
| 影响 | 误报与耗时 |
| 建议 | 按分类分桶比较，缓存特征向量并以图片哈希判断是否失效 |

#### M-11 批量录入的取消与内存问题

| 项目 | 内容 |
|---|---|
| 位置 | `Views/BatchImportView.swift:36-41`、`:59`；`ViewModels/ItemDraftModel.swift:114-127`；`Views/WardrobeGalleryView.swift:137-143` |
| 证据 | 跳过时只改变 `index`，被取消的任务中没有取消检查，`VisionService` 是串行 actor，已提交的抠图仍会执行完。文件与拖拽来源在进入编辑器前就全部读入内存。读取失败的文件被丢弃且不提示 |
| 问题 | 快速跳过多张时，当前图片要排在已放弃的任务之后。大批量文件同时驻留内存 |
| 影响 | 批量体验变慢，内存峰值高，用户不知道哪些文件没有导入 |
| 建议 | 在处理流程中检查取消；来源改为延迟读取；对失败文件给出清单。Web 版由任务队列天然解决 |

#### M-12 差旅流程与日常流程隔离过度

| 项目 | 内容 |
|---|---|
| 位置 | `Models/ClothingItem.swift:140`；`Services/OutfitGeneratorService.swift:48`；`Views/Outfit/ManualOutfitBuilderView.swift:27`；`Services/WearService.swift:121-128`；`Services/TravelService.swift:7-10`；`Models/Enums/Category.swift:10-15` |
| 证据 | 生成与拼搭都只接受在衣橱状态。结束差旅把全部 `inLuggage` 改回 `inWardrobe`。差旅页显示内裤数量，但分类中没有内衣类 |
| 问题 | 出差期间无法用行李箱里的衣服生成或记录穿搭；旅途中穿过的衣服结束差旅后直接回衣橱，不经过洗衣袋 |
| 影响 | 差旅功能只覆盖装箱，不覆盖旅途和返程 |
| 建议 | 增加差旅模式，期间以行李箱为可用池；结束差旅时提供逐件选择入洗衣袋 |

#### M-13 视图状态持有过期的模型引用

| 项目 | 内容 |
|---|---|
| 位置 | `Views/Outfit/OutfitGeneratorView.swift:14`；`Views/TravelCapsuleView.swift:14`、`:145-149`；`Views/DuplicationView.swift:13` |
| 证据 | 生成结果、差旅建议、相似分组都以 `ClothingItem` 引用保存在 `@State` 中，数据变化时不重新计算 |
| 问题 | 生成结果出来后，单品被放入洗衣袋，仍可从旧结果收藏或穿着；差旅建议中的单品状态改变后，一键装箱仍会处理它们。访问已删除模型对象时 SwiftData 的运行时表现，Repository 中没有足够信息确认这一点 |
| 影响 | 状态被旧结果覆盖 |
| 建议 | 执行操作前按 id 重新读取并校验状态 |

#### M-14 原图元数据原样保存并随备份导出

| 项目 | 内容 |
|---|---|
| 位置 | `ViewModels/ItemDraftModel.swift:116`；`Services/BackupService.swift:94`、`:126-129` |
| 证据 | 原始字节直接写入 `originalImageData`，没有剥离 EXIF 的步骤。备份内联原图 base64。导出文件写入临时目录后没有清理 |
| 问题 | 原图中携带的元数据会进入数据库和备份文件。PhotosPicker 返回的数据是否包含 GPS 信息，Repository 中没有足够信息确认这一点；从文件和拖拽导入的数据是原始文件字节 |
| 影响 | 通过分享导出的备份会携带原图元数据 |
| 建议 | 入库时生成去除元数据的派生图用于展示和备份，原图是否保留交给用户决定，见第 11 节 D4 |

#### M-15 旧数据的保暖字段不一致

| 项目 | 内容 |
|---|---|
| 位置 | `Models/ClothingItem.swift:56`、`:59`；提交 `d83fc17` 对 `ClothingItem.swift` 的差异 |
| 证据 | 提交 `76f05d6` 中 `warmthLevels` 是用户多选的标签。提交 `d83fc17` 新增 `warmthScore`，默认值 50，生成算法改为只看 `warmthScore` |
| 问题 | 在 `d83fc17` 之前录入的单品，升级后 `warmthScore` 全部为 50，`warmthLevels` 保留旧的多选值，两者不一致 |
| 影响 | 这些单品在生成算法中全部按中等保暖处理。设备上是否存在这一时期的数据，Repository 中没有足够信息确认这一点 |
| 建议 | 导出前提供一次性校正工具，或在 Web 导入预检中列出 `warmthScore == 50` 且 `warmthLevels` 与之不对应的单品 |

#### M-16 自动命名的颜色与卡片显示的颜色不一致

| 项目 | 内容 |
|---|---|
| 位置 | `Models/ClothingItem.swift:133-137`；`Views/Components/ItemCard.swift:126`；`Views/Components/ItemFormSections.swift:197` |
| 证据 | 默认名称使用 `ColorCategory.classify` 的粗分类，卡片与表单显示 `refinedColorName` 的精细色名。按两者公式逐项计算 `ColorNaming` 表中的参考色，驼色归入 `orange`，桃粉归入 `red`，橄榄绿归入 `yellow` |
| 问题 | 一件驼色大衣的自动名称是橙色大衣，卡片色名显示驼色 |
| 影响 | 名称与显示矛盾，名称会进入备份和搜索 |
| 建议 | 默认名称改用精细色名，或让两个体系共用一张映射表 |

#### M-17 九十天未穿把新录入的单品计入

| 项目 | 内容 |
|---|---|
| 位置 | `Views/WardrobeSearchView.swift:19-30`、`:45-49` |
| 证据 | 判定条件只看最近 90 天内有没有穿着记录，没有考虑 `createdAt`。结果网格的卡片没有点击处理 |
| 问题 | 昨天刚录入的单品会出现在吃灰列表里；筛选出来的单品无法直接打开编辑 |
| 影响 | 筛选结果失真，操作链断开 |
| 建议 | 条件改为录入时间早于 90 天且最近 90 天未穿；结果卡片支持打开编辑 |

#### M-18 业务规则分散在视图层

| 项目 | 内容 |
|---|---|
| 位置 | `Views/WardrobeGalleryView.swift:44-54`；`Views/LaundryView.swift:17-19`、`:100-103`；`Views/WardrobeSearchView.swift:19-30`；`Views/TravelCapsuleView.swift:127-143`；`Views/Outfit/ManualOutfitBuilderView.swift:17-33`；`Views/Analytics/AnalyticsDashboardView.swift:109-116`、`:159-176`；`Views/Components/ItemFormSections.swift:237-241` |
| 证据 | 状态隔离规则、4 天滞留阈值、90 天吃灰阈值、差旅去重、必选槽位、颜色桶代表色都写在视图中。必选槽位在 `ManualOutfitBuilderView` 中重复定义了一遍，`Category.isRequiredInOutfit` 已有同样信息。场景冲突检查在 `ClothingItem.hasScenarioConflict` 与 `ItemFormSections` 中各写一份 |
| 问题 | 规则无法单独测试，Web 移植时需要逐个视图挖出规则 |
| 影响 | 移植遗漏风险 |
| 建议 | Phase 1 把这些规则移入领域核心，视图只调用 |

#### M-19 服务与持久化框架、UI 框架耦合

| 项目 | 内容 |
|---|---|
| 位置 | `Models/ImageSource.swift:3`、`:12`；`Models/Support/StoredColor.swift:2`、`:25-27`；`Models/Enums/GalleryItemSize.swift:1`；`Models/Enums/UIPreferences.swift:1`；`Services/WearService.swift` 全部函数签名；`ViewModels/ItemDraftModel.swift:118`、`:136` |
| 证据 | 模型层引用 `PhotosPickerItem` 和 SwiftUI `Color`，UI 偏好枚举放在 Models 目录。服务入参是 `ModelContext` 与 `@Model` 类。`ItemDraftModel` 直接使用 `VisionService.shared` 单例 |
| 问题 | 领域逻辑离不开 SwiftData 和 SwiftUI，无法在普通单元测试或服务端复用 |
| 影响 | 增加测试与移植成本 |
| 建议 | 领域核心只使用值类型，图片处理通过协议注入，见 Phase 1 |

### 3.4 Low

| 编号 | 位置 | 证据与问题 | 建议 |
|---|---|---|---|
| L-01 | `Models/Enums/ColorCategory.swift:11`、`:42-71` | `multicolor` 存在但 `classify` 从不返回它 | 删除或实现多色判定 |
| L-02 | `Services/VisionService.swift:122`、`:170` | 取色位图使用 `premultipliedLast`，只跳过 alpha 小于 32 的像素，半透明边缘像素按预乘值参与平均，颜色偏暗 | 求均值前反预乘，或只统计 alpha 为 255 的像素 |
| L-03 | `docs/DEVELOPMENT.zh-CN.md:27`；`project.pbxproj:181`、`:239`、`:264`、`:297`；`Views/WardrobeGalleryView.swift:150`、`:155` | 文档声称适配 macOS 14，工程只有 iOS 目标，`.topBarLeading` 没有平台条件编译。工程级部署目标 26.5 与目标级 17.0 不一致 | 修正文档，统一部署目标设置 |
| L-04 | 多处 | 未被引用的代码有 `ComingSoonView`、`Outfit.isStructurallyValid`、`missingRequiredSlots`、`Outfit` 的槽位访问器、`isSuitable(forWarmth:)`、`isSuitable(forScenario:)`、`StoredColor.hexString`、`BatchImportView.savedCount`、`Outfit.canvasLayoutData` 的写入 | 删除或接入，`isStructurallyValid` 应接入 H-03 的修复 |
| L-05 | `ItemCard.swift:18-20`、`ItemThumbnail.swift:8-10`、`ItemDraftModel.swift:67`、`DuplicationView.swift:87`；`VisionService.swift:178-181` 与 `DuplicationDetectorService.swift:93-96`；四个视图中的 `showToast` | 图片回退、CGImage 解码、颜色距离、安全作用域读取、toast 均有重复实现 | 抽取公共实现 |
| L-06 | `FavoritesView.swift:81-87` 等四处 | 连续触发 toast 时，前一个任务会提前清除后一个提示 | 用可取消任务或计数器 |
| L-07 | `VisionService.swift:68`、`:87`；全仓库 18 处 `try?`，其中 4 处用于 `Task.sleep` | 只有 `print` 日志，多数错误被静默吞掉 | 引入统一日志与错误上报到界面 |
| L-08 | `docs/DEVELOPMENT.zh-CN.md:274` | 文档要求对 `project.pbxproj` 执行 `git update-index --skip-worktree`，之后增加测试目标等合法工程改动不会被 git 察觉 | 增加测试目标前先执行 `--no-skip-worktree`，或改用 xcconfig 存放团队 ID |
| L-09 | `Assets.xcassets/AppIcon.appiconset/Contents.json` | 三个图标槽位都没有图片文件 | 补充图标 |
| L-10 | `Views/Analytics/ColorTreemapView.swift:8` | `Tile` 的 `id` 在每次构造时生成新 UUID，每次重绘身份都变化 | 用颜色桶原始值作为 id |
| L-11 | `Views/Components/ItemFormSections.swift:308` | 注释写防水开关适用于内衣裤，分类中没有内衣类 | 修正注释 |

### 3.5 按审查类别的索引

| 类别 | 对应编号 |
|---|---|
| A. Functional bugs | H-01、H-02、H-03、M-01、M-02、M-04、M-05、M-07、M-08、M-09、M-12、M-13、M-16、M-17、L-01、L-02 |
| B. Architecture problems | H-05、M-06、M-18、M-19、L-04、L-05 |
| C. Database problems | C-01、H-05、M-02、M-03、M-06、M-15，以及第 3.6 节 |
| D. Security problems | M-14，以及第 3.7 节与第 8.4 节 |
| E. Performance problems | C-01、H-04、H-06、M-10、M-11，以及第 3.8 节 |
| F. Maintainability | C-02、M-18、M-19、L-03 至 L-11，以及第 3.9 节 |

### 3.6 Database 专项

Schema 设计上，三实体加两个多对多关系对当前功能够用，问题集中在约束完全缺失。数据库层没有约束保证至多一条活动记录、入袋时间与状态的对应、子类与分类的匹配、`warmthScore` 在 1 到 100 之间。这些规则全部依赖界面路径，任何新路径都会绕过它们，H-03、M-01、M-02 都是这一结构问题的具体表现。

索引方面，除了 `.unique` 的 id，没有声明任何索引。因为按状态和分类的过滤都在内存中完成，目前索引对性能没有作用。Web 版需要按状态、分类、日期查询，索引需要从一开始设计。

事务方面，全仓库没有 `save()`，多步操作没有显式事务边界。`BackupService.apply` 中的覆盖导入是先全删后插入的同步序列，由 autosave 统一落盘，过程中没有可回滚的错误路径，因为 `insert` 不抛错，但也没有任何校验失败后放弃的机制。

并发方面，所有写操作都通过主线程的 `modelContext` 完成，单进程单界面下不存在并发写冲突。Web 版允许多个浏览器标签同时操作，需要乐观锁或版本字段。

重复数据方面，相同图片可以被重复录入，相似检测只能事后发现。Web 版可以按图片内容哈希在上传时提示重复。

### 3.7 Security 专项，当前 iOS 版

当前应用没有网络代码、没有子进程、没有 SQL 拼接、没有凭据。`DEVELOPMENT_TEAM` 在仓库中为空字符串，没有发现密钥或令牌。攻击面集中在两处。备份导入接受任意文件，整体读入并解码，没有大小上限，构造的超大文件会耗尽内存。原图元数据未剥离，见 M-14。用户画像中的身高、体重、年龄、性别以明文存在 UserDefaults 中，不在备份内。

### 3.8 Performance 专项

除 C-01、H-04、H-06、M-10、M-11 外还有以下几点。`AnalyticsDashboardView.swift:13-24` 的四个计算属性在 `body` 中被多次读取，每次读取都完整重算。`AnalyticsService.colorFrequency` 遍历每条记录的 `items`，`WardrobeSearchView.swift:28` 遍历每个单品的 `wearRecords`，都是逐条触发关系加载。`WearService.unpackAllLuggage` 取出全部单品再在内存中过滤。原图从不缩放，抠图对全分辨率原图执行。项目中不存在 PDF 处理。

### 3.9 Maintainability 专项

文件规模合理，最大的 `ItemFormSections.swift` 为 328 行，没有超长函数。类型方面，领域枚举设计扎实，备份 DTO 中枚举却退化为字符串，这是 M-02 的根源之一。错误处理不一致，`VisionService` 定义了带中文文案的错误类型，其余服务大量使用 `try?`。文档整体与代码一致，例外是 L-03 与 L-11。项目约定写在 `docs/DEVELOPMENT.zh-CN.md`，没有 `CLAUDE.md`，后续若使用 Claude Code 协作，建议把第 9 节迁移策略和硬性原则同步写入。

---

## 4. Testing Review

### 4.1 现状

仓库中不存在任何测试。没有单元测试、集成测试、端到端测试、数据库测试、文件系统测试、UI 测试，也没有 SwiftUI 预览。项目中不存在 PDF 处理，因此也不存在 PDF 测试。本轮无法执行任何测试，原因是测试不存在；也无法执行构建，原因见第 1.1 节。

### 4.2 关键功能的测试缺口

| 功能 | 关键代码 | 现有测试 | 需要的测试类型 | 可否脱离设备运行 |
|---|---|---|---|---|
| 叠穿生成 | `OutfitGeneratorService.generate`、`buildTorso` | 无 | 单元，注入随机源后的黄金样本 | 可以 |
| 颜色归类与命名 | `ColorCategory.classify`、`ColorNaming.name`、`StoredColor.hsb` | 无 | 表驱动单元 | 可以 |
| 保暖映射与季节推导 | `WarmthLevel.from`、`Season.derive` | 无 | 边界值单元，覆盖 16、17、33、34、50、51、67、68、84、85 | 可以 |
| 差旅数量 | `TravelService` | 无 | 单元 | 可以 |
| 统计 | `AnalyticsService` | 无 | 单元 | 可以 |
| 状态流转 | `WearService` | 无 | 内存容器集成测试，含 H-03 与 M-01 的复现 | 可以，需要 SwiftData |
| 备份往返 | `BackupService` | 无 | 内存容器集成测试，覆盖覆盖、合并、未知枚举、活动记录冲突 | 可以，需要 SwiftData |
| 草稿模型 | `ItemDraftModel` | 无 | 单元，含 M-04 | 可以 |
| 抠图与取色 | `VisionService` | 无 | 真机或 macOS 主机上的图像夹具测试 | 取色可以，抠图需要真机 |
| 相似检测 | `DuplicationDetectorService` | 无 | 图像夹具测试，阈值回归 | 需要真机或 macOS |
| 主要流程 | 录入、生成、穿着、脱下、洗衣 | 无 | XCUITest | 需要模拟器 |

### 4.3 对测试策略的建议

第一批测试的目标不是覆盖率，而是把当前行为固定下来，作为修复和移植的对照基准。对已知有缺陷的行为，例如 H-02 与 M-07，先写一个记录当前输出的特征测试，修复时再把断言改为正确行为，这样每一处行为变化都有明确记录。黄金样本以 JSON 文件保存，内容是输入单品集合、随机种子和期望输出，Web 版后端直接读取同一批文件做一致性测试。

---

## 5. Feature Inventory

### 5.1 Existing

| 功能 | 主要位置 |
|---|---|
| 单件录入，相册或文件选图，Vision 抠图，主辅色提取，颜色加子类自动命名，吸管调色 | `ItemEditorView`、`ItemFormSections`、`ItemDraftModel`、`VisionService` |
| 批量录入，相册最多 30 张，文件多选，拖拽释放，逐张编辑 | `WardrobeGalleryView`、`BatchImportView` |
| 衣橱网格，分类过滤，大中小三档，洗衣袋显示开关，行李箱隔离 | `WardrobeGalleryView`、`GalleryItemSize` |
| 智能生成，6 档保暖，4 种场景，雨雪防水约束，横滑浏览 | `OutfitGeneratorView`、`OutfitGeneratorService` |
| 收藏，今天穿这套，正在穿看板，脱下弹窗与智能默认勾选 | `FavoritesView`、`ActiveOutfitWidget`、`TakeOffSheet`、`WearService` |
| 洗衣房，全选，洗净放回，超过 4 天预警 | `LaundryView` |
| 穿着历史列表与删除 | `CalendarHistoryView` |
| 看板，分类库存、颜色树形图、色彩偏好、16 周热力图 | `AnalyticsDashboardView` 及子视图 |
| 高级筛选，场景、主色、防水、90 天未穿 | `WardrobeSearchView` |
| 外观设置，强调色、外观模式、卡片圆角 | `SettingsView`、`UIPreferences` |
| 相似单品检测与删除 | `DuplicationView`、`DuplicationDetectorService` |
| 备份导出与导入，覆盖或合并 | `SettingsView`、`BackupService` |

### 5.2 Partially implemented

| 功能 | 限制 | 依据 |
|---|---|---|
| 自由拼搭 | 只能按槽位选择，自由画布未实现 | `docs/DEVELOPMENT.zh-CN.md:285`，`Outfit.canvasLayoutData` 无写入 |
| 日历 | 只有倒序列表，没有月历；记录备注字段没有界面 | `CalendarHistoryView.swift:6`，`WearRecord.notes` |
| 用户画像 | 只存储不使用 | `SettingsView.swift:84`，`docs/DEVELOPMENT.zh-CN.md:286` |
| 季节 | 只存储不参与任何逻辑，未拖动保暖滑条时保存为空 | M-04，H-02 |
| 收藏 | 名称固定为收藏穿搭，不能重命名，不校验完整性，来源记录错误 | `WearService.swift:20`，H-03，M-05 |
| 相似检测 | 跨分类，不缓存，只能删除不能合并 | M-10 |
| 差旅 | 只覆盖装箱，旅途与返程不支持 | M-12 |
| 高级筛选 | 无文本搜索，结果不可编辑，吃灰判定有误 | M-17 |
| 备份 | 只有手动，合并只插入，不含设置与画像 | C-01，M-02 |
| 颜色归类 | 多色桶不可达，命名两套体系不一致 | L-01，M-16 |


### 5.3 Broken / unreliable

| 功能 | 问题编号 |
|---|---|
| 新录入单品参与智能生成 | H-01 |
| 生成结果符合天气 | H-02 |
| 从收藏穿着后的状态流转 | H-03 |
| 通过编辑器改变洗衣状态 | M-01 |
| 大衣橱下的网格浏览 | H-04 |
| 大数据量下的备份导出 | C-01 |
| 合并导入后的正在穿状态 | M-02 |
| 拖拽导入的数据校验 | M-08 |

### 5.4 Missing

| 功能 | 依据 |
|---|---|
| 自动化测试与 CI | C-02 |
| 缩略图 | `docs/DEVELOPMENT.zh-CN.md:282` |
| 删除确认与撤销 | M-09 |
| 手动放入洗衣袋 | M-01 |
| 文本搜索 | 单品已有 `name`、`brand`、`notes` 字段，没有搜索入口 |
| 单品穿着次数与最后穿着日期 | `WearRecord.swift:9` 注释写明后续用于穿着频率分析 |
| 月历视图 | `CalendarHistoryView.swift:6` |
| 用原图重新抠图 | `ClothingItem.swift:37` 注释写明保留原图以便后续重新抠图 |
| 自动备份 | 当前只有手动冷备份 |
| Schema 版本化迁移 | H-05 |

按项目原则不应加入的功能有两类。联网天气与任何联网服务，依据是 `docs/DEVELOPMENT.zh-CN.md:26`。价格、成本、单次穿着成本统计，依据是 `AnalyticsService.swift:5` 与 `AnalyticsDashboardView.swift:8` 的明确排除。

---

## 6. Web Migration Assessment

### 6.1 各层距离

| 层 | 现状 | Web 化所需工作 | 距离 |
|---|---|---|---|
| UI | SwiftUI 2,844 行 | 全部重写为浏览器前端 | 远 |
| 状态与导航 | TabView、sheet、@Observable | 前端路由与状态管理重写 | 远 |
| 领域逻辑 | 纯逻辑，但依赖 `@Model` 类 | 解耦后复用或移植 | 近 |
| 持久化 | SwiftData，无约束，无迁移计划 | 新建 SQLite schema 与迁移 | 中 |
| 图片智能处理 | Apple Vision 与 CoreImage | macOS 分支复用，跨平台分支替换模型 | 由 D1 决定，近或远 |
| 文件处理 | 安全作用域 URL、PhotosPicker、拖拽 Data | 上传接口与媒体存储 | 中 |
| 后台任务 | 两个 actor | 持久化任务队列与进度推送 | 中 |
| API | 不存在 | 全新设计 | 中 |
| 安全 | 单设备沙盒，无需鉴权 | Host 与 Origin 校验、上传校验、输出转义 | 中 |
| 测试 | 不存在 | 从零建立 | 远 |
| 数据迁移 | 只有 `.wardrobe` v1 | 导入器与预检 | 近，前提是 C-01 已修复 |

总体判断，当前架构距离 Local Web Application 属于中等偏远。工作量主要在 UI 重写与基础设施建设，业务规则本身体量小、边界清楚，移植风险可控，前提是先用测试把规则固定。

### 6.2 三种方案对比

| 维度 | Option A 现有应用加 Web UI | Option B 独立后端 API 加独立前端 | Option C 单进程本地 Web 应用 |
|---|---|---|---|
| 与仓库的契合度 | 现有应用是 iOS 应用。要在 iOS 应用里内嵌 HTTP 服务，应用进入后台后系统会挂起它，服务随之中断；要做成 macOS 宿主应用，就成了需要安装的桌面程序，与不要求下载传统桌面程序的目标冲突 | 契合，但两个进程、两个端口、跨域配置，对单用户本地工具是额外负担 | 契合，一个进程、一个端口、一个数据目录 |
| 代码复用 | 最高，但 UI 仍需用 Web 技术重写 | 与 C 相同 | 与 B 相同 |
| 打包与启动 | 需要签名与安装 | 需要同时启动两个服务，或由后端托管前端，后者即为 C | 一条启动命令 |
| 安全面 | 若开放局域网访问，iOS 端无法做完整的服务端加固 | 跨域配置稍有不慎就会对任意网页开放 | 同源，最容易做 Host 与 Origin 校验 |
| 可测试性 | 低 | 高 | 高，API 层可直接做集成测试 |
| 结论 | 不推荐 | 作为内部分层方式采用 | 推荐作为部署形态 |

推荐结论是 Option C 的部署形态，配合 Option B 的内部边界。前端只通过版本化的 JSON API 访问后端，不直接渲染数据库对象，这样将来如果需要让 iOS 应用与 Web 版同步，API 已经存在。

### 6.3 后端语言的两条分支

| 维度 | 分支 M，macOS 专用，Swift 服务端 | 分支 X，跨平台，Python 服务端 |
|---|---|---|
| 抠图 | 直接复用 `VisionService`，效果与 iOS 版一致 | 改用本地 ONNX 前景分割模型，效果需要用真实衣物图重新验收 |
| 相似检测 | 直接复用，阈值 0.6 与 0.30 沿用 | 改用图像嵌入模型，阈值必须重新标定 |
| 取色与生成算法 | 抽成共享 Swift 包，iOS 与服务端共用一份 | 按黄金样本移植 |
| HEIC 支持 | ImageIO 原生支持 | 需要额外的 HEIF 解码库 |
| 运行平台 | 只能 macOS 14 及以上 | Windows、Linux、macOS |
| 生态 | Swift 服务端框架与 SQLite 库可用，前端仍是 TypeScript | 图像与模型生态成熟 |
| 离线要求 | 天然满足 | 模型文件必须随安装提供，运行时不得联网下载 |

README 与开发文档要求 Xcode 26 以上，说明开发者本人有 macOS 环境，这一点可以从 `README.md:19` 确认。Web 版是否需要在其它系统上运行，Repository 中没有足够信息确认这一点，因此第 11 节把它列为 D1 待决问题。在 D1 未决之前，Phase 0 与 Phase 1 的工作两条分支完全相同，可以先行开展。

---

## 7. Target Architecture

### 7.1 总体结构

```text
Browser
  单页应用，静态资源随应用打包
  页面：衣橱 / 单品编辑 / 批量录入 / 洗衣房 / 穿搭 / 日历 / 看板 / 设置
      │  /api/v1/*  JSON
      │  /api/v1/uploads  multipart
      │  /api/v1/events  SSE 任务进度
      ▼
Local Server，单进程，默认只监听 127.0.0.1
  HTTP 层        路由，请求 schema 校验，Host 与 Origin 校验，CSRF，错误映射，CSP 头
  应用服务层      ItemService，LifecycleService，OutfitService，TravelService，
                 AnalyticsService，BackupService，MediaService
  领域核心        生成算法，颜色归类与命名，保暖档位与季节，差旅规则，统计，状态机规则
  任务队列        jobs 表持久化，启动时恢复未完成任务，图像类任务串行或限并发
  仓储层          SQLite，WAL，所有写操作在事务中完成，乐观锁版本字段
  媒体存储        <DATA_DIR>/media/...，文件名由服务端按 UUID 生成
```

### 7.2 Browser

| 关注点 | 设计 |
|---|---|
| 页面结构 | 与现有五个 Tab 一一对应，另加单品编辑、批量录入、设置子页。桌面宽屏用左侧导航，窄屏用底部导航 |
| Navigation | URL 路由，筛选条件写入查询参数，刷新与分享链接都能还原状态 |
| Forms | 单品表单字段与 `ItemFormSections` 一致；前端做即时校验，后端做权威校验；场景至少一个的规则按 H-01 的决策执行 |
| Tables | 穿着历史、备份导入预检报告、相似分组使用表格；衣橱主体仍为卡片网格 |
| File upload | 拖拽区与多选文件框，前端预检类型与大小，逐文件显示上传与处理进度，失败文件单独列出 |
| 图片预览 | 列表只加载缩略图；编辑页可切换原图与抠图结果。仓库中不存在 PDF 功能，不需要 PDF 预览 |
| Search | 文本搜索名称、品牌、备注，见 P1-4 |
| Filtering | 状态、分类、场景、主色、防水、未穿天数，全部由后端执行 |
| Progress indicators | 上传进度来自浏览器，处理进度来自任务事件流 |
| Error display | 表单错误就地显示；操作失败用提示条；后端统一返回错误码与中文文案；未处理异常进入错误页并保留重试入口 |

### 7.3 Backend

API 以动作而不是字段修改来表达状态流转，这样状态机不变量只在一处实现。

| 资源 | 端点 |
|---|---|
| 单品 | `GET /api/v1/items`，`POST /api/v1/items`，`GET`、`PATCH`、`DELETE /api/v1/items/{id}`，`POST /api/v1/items/{id}/image`，`POST /api/v1/items/{id}/reprocess` |
| 状态流转 | `POST /api/v1/items/{id}/transitions`，请求体给出目标状态，服务端维护入袋时间并校验来源状态 |
| 媒体 | `GET /api/v1/media/{imageId}?variant=thumb` 等，按 id 查表取路径 |
| 批量录入 | `POST /api/v1/uploads` 返回上传 id 与任务 id，`POST /api/v1/import-batches` 管理一批 |
| 穿搭 | `POST /api/v1/outfits/generate`，请求体含 `warmth`、`scenario`、`requireWaterproof`、`maxCount`、可选 `seed`；`GET`、`POST`、`PATCH`、`DELETE /api/v1/outfits` |
| 穿着 | `POST /api/v1/wear-records`，`GET /api/v1/wear-records/active`，`POST /api/v1/wear-records/{id}/take-off` |
| 洗衣 | `POST /api/v1/laundry/return` |
| 差旅 | `POST /api/v1/travel/suggest`，`POST /api/v1/travel/pack`，`POST /api/v1/travel/finish` |
| 看板 | `GET /api/v1/analytics/summary` |
| 相似检测 | `POST /api/v1/duplicates/scan` 返回任务 id，`GET /api/v1/duplicates/latest` |
| 备份 | `POST /api/v1/backups/export`，`GET /api/v1/backups/{id}/download`，`POST /api/v1/backups/import?mode=overwrite或merge&dryRun=true` |
| 设置 | `GET`、`PUT /api/v1/settings` |
| 任务 | `GET /api/v1/jobs/{id}`，`GET /api/v1/events` |

请求校验在 HTTP 层用 schema 完成，枚举只接受第 2.4 节列出的原始值。业务逻辑在应用服务层，每个用例一个事务。文件处理全部进入任务队列，接口立即返回任务 id。数据库访问只在仓储层，使用参数化查询。后台任务记录在 `jobs` 表中，进程重启后继续执行未完成的任务。

### 7.4 Database

现有 SwiftData 存储位于 iPhone 应用沙盒内，Web 版无法直接打开它，因此不保留原存储，数据通过 `.wardrobe` 文件迁移。新建 SQLite schema，结构建议如下。

| 表 | 关键字段与约束 |
|---|---|
| `items` | `id` 主键，`category` 与 `status` 带 CHECK，`subtype` 可空，`warmth_score` CHECK 1 到 100，`laundry_entry_at` 可空，主色与辅色分量，`dominant_color_category`，`brand`，`notes`，`created_at`，`updated_at`，`deleted_at` 软删除，`version` 乐观锁。CHECK 保证 `status = 'inLaundry'` 与 `laundry_entry_at` 非空互相对应 |
| `subtypes` | 子类原始值与所属分类的对照表，`items` 以复合外键保证子类与分类匹配 |
| `item_scenarios`、`item_seasons` | 关联表，外键级联删除 |
| `images` | `id`，`item_id`，`kind` 取 original、processed、thumb，相对路径，`mime`，宽高，字节数，`sha256` |
| `outfits` | 对应 `Outfit`，`source` 带 CHECK，`canvas_layout` JSON 可空 |
| `outfit_items` | `outfit_id`，`item_id`，`slot` 取 outerwear、mid、base、bottom、socks、shoes、accessory，`position`，用于解决 M-06 |
| `wear_records` | `worn_on` 本地日期，`worn_at` 时间戳，`is_active`，`outfit_id` 外键置空，`notes`。部分唯一索引保证至多一条 `is_active = 1` |
| `wear_record_items` | 关联表，额外保存 `slot` |
| `settings` | 画像与外观设置，键值 JSON，纳入备份 |
| `feature_vectors` | 相似检测特征缓存，含模型标识与图片哈希 |
| `jobs` | 任务类型、状态、进度、输入、结果、错误 |
| `schema_migrations` | 已应用的迁移版本 |

索引建议为 `items(status, category)`、`items(dominant_color_category)`、`wear_records(worn_on)`、`outfit_items(item_id)`、`wear_record_items(item_id)`、`outfits(is_favorite, created_at)`。

迁移策略是版本化 SQL 迁移文件，进程启动时在事务中按序执行，执行前自动复制一份数据库文件到 `backups/pre-migration/`。iOS 数据迁移的流程是 iOS 应用导出 `.wardrobe`，Web 版导入预检，输出数量、未知值、缺失图片、HEIC 转码、M-15 保暖异常清单，用户确认后正式导入。

### 7.5 Files

```text
<DATA_DIR>/
  closet.sqlite  closet.sqlite-wal  closet.sqlite-shm
  media/original/<前两位>/<uuid>.<ext>
  media/processed/<前两位>/<uuid>.png
  media/thumb/<前两位>/<uuid>.webp
  tmp/uploads/
  exports/
  backups/auto/
  backups/pre-migration/
  logs/
```

| 类型 | 管理方式 |
|---|---|
| Uploaded files | 先写入 `tmp/uploads`，完成类型嗅探、解码校验、像素上限检查后移入 `media/original`；文件名由服务端生成，原始文件名只作为元数据保存 |
| Processed files | 抠图结果保存为 PNG，位于 `media/processed` |
| Generated files | 缩略图与浏览器兼容的展示图位于 `media/thumb`，去除元数据；HEIC 原图在此生成可显示版本 |
| Temporary files | 启动时与定时清理 `tmp`，上传会话超时后删除 |
| Backup files | 自动备份按份数轮转保存在 `backups/auto`；手动导出写入 `exports` 并在下载后按保留期清理；迁移前快照在 `backups/pre-migration` |

`DATA_DIR` 默认放在用户目录下的应用数据位置，可通过启动参数覆盖，不写入仓库目录。

---

## 8. Web 化风险

### 8.1 Desktop-specific assumptions

当前程序是 iOS 应用，下表列出所有平台专属的假设。仓库中没有硬编码路径，没有操作系统命令，没有启动外部进程，唯一使用的系统路径是临时目录。

| 假设 | 位置 | Web 版处理方式 |
|---|---|---|
| SwiftUI 界面与触控交互，含 sheet、contextMenu、左滑删除、横滑分页 | `Views/*` | 重写为网页交互，左滑删除改为显式按钮 |
| SwiftData 持久化，`@Query` 自动刷新 | 全部视图与服务 | SQLite 加 API，前端用请求缓存与失效刷新 |
| Vision 抠图与特征指纹 | `VisionService.swift:62-89`，`DuplicationDetectorService.swift:81-91` | 由 D1 决定 |
| CoreImage、CVPixelBuffer、ImageIO、CoreGraphics | `VisionService.swift` 全文 | 后端图像库 |
| PhotosPicker 与 `PhotosPickerItem` | `ImageSource.swift:12`，`ItemFormSections.swift:40`，`WardrobeGalleryView.swift:106-111` | 文件选择框，手机浏览器上可唤起相册 |
| 安全作用域文件访问 | `WardrobeGalleryView.swift:139-140`，`ItemFormSections.swift:54-55`，`BackupService.swift:136-137` | 不需要，浏览器上传 |
| `.dropDestination(for: Data.self)` | `WardrobeGalleryView.swift:76-80` | HTML 拖放，只接受文件 |
| `ShareLink` 与临时目录 | `SettingsView.swift:137-141`，`BackupService.swift:126-128` | 下载链接 |
| `ColorPicker` 系统吸管与 `Color.resolve(in:)` | `ItemFormSections.swift:180`、`:203-216` | 颜色输入框；网页吸管接口并非所有浏览器都提供，需要在目标浏览器上验证 |
| `@AppStorage` | 第 2.1 节所列 8 个键 | 外观偏好可放浏览器本地，画像放 `settings` 表并纳入备份 |
| Swift Charts | `AnalyticsDashboardView.swift` | 网页图表库；树形图与热力图已有自定义布局算法，可直接移植 |
| `Calendar.current` 与本地时区 | `AnalyticsService.swift:42-45`，`ActivityHeatmapView.swift:12-29` | 记录同时保存本地日期与时间戳，按日聚合使用本地日期 |
| 模拟器提示 | `VisionService.swift:40-46` | 删除 |
| 启动失败即终止 | `ClosetSchema.swift:26` | 服务端返回维护页并保留数据 |
| 单进程单界面，无并发写 | 全部写路径 | 事务加乐观锁 |

### 8.2 Browser limitations

浏览器无法直接调用 Vision，也无法写入本机任意目录，所以抠图、取色、缩略图、相似检测、备份读写都必须放在后端服务中完成。iPhone 照片常见的 HEIC 格式在多数非 Safari 浏览器中无法直接显示，后端必须生成可显示的派生图。浏览器端的吸管取色接口支持范围有限，需要在你实际使用的浏览器上验证。大文件上传需要分块或流式处理，不能整体读入内存。生成算法是纯计算，放在后端执行可以与测试共享同一实现，不建议在前端再实现一份。

### 8.3 数据迁移风险

`.wardrobe` v1 内联全部原图，文件体积大，导入器必须流式解析。M-02 与 M-15 指出的数据质量问题会随导出进入 Web 版，所以预检报告是必要步骤。M-03 的往返行为需要先在 iOS 端验证，再拿真实导出文件做 Web 端导入演练。

### 8.4 Web 化后新增的安全要求

| 风险 | 要求 |
|---|---|
| 本机服务被其它网页访问 | 默认只监听 127.0.0.1；校验 `Host` 头只接受 `127.0.0.1` 与 `localhost` 加端口，用于防御 DNS rebinding；不开启宽松 CORS |
| CSRF | 所有写操作校验 `Origin`，会话 cookie 使用 `SameSite=Strict`，并要求 CSRF token |
| 鉴权 | 仅本机访问时可以不设登录；若需要手机通过局域网访问，必须显式开启，并使用配对令牌或密码，见 D2 |
| 文件上传 | 限制单文件大小、批量数量、像素总数；按文件头嗅探类型，只接受 JPEG、PNG、HEIC、HEIF、WebP；拒绝 SVG，SVG 可携带脚本；全部重新编码后再展示 |
| 路径穿越 | 存储路径只由服务端 UUID 生成；媒体接口按 id 查表，不接受路径参数；关闭目录列表 |
| XSS | 名称、品牌、备注、导入 JSON 中的字符串一律转义输出；设置 CSP，`default-src 'self'` |
| SQL 注入 | 只使用参数化查询 |
| 命令执行 | 不调用 shell；如必须调用外部工具，使用参数数组并固定可执行文件路径 |
| 备份导入 | 限制文件大小，schema 校验，枚举严格匹配，base64 解码后再次做图片校验 |
| 配置暴露 | 不提供调试端点，错误响应不含堆栈与本机路径，日志不记录图片内容与画像数据 |
| 离线原则 | 前端资源、字体、模型文件全部本地提供，不加载任何外部 CDN，不发送遥测 |

---

## 9. Feature Roadmap

复杂度按改动范围分为低、中、高。低指单个模块内的修改，中指跨两到三个模块或需要新增数据字段，高指需要新子系统。

### 9.1 P0 必须解决

| 编号 | 功能 | 为什么需要与解决的问题 | 对架构的影响 | Web 化后是否更容易 | 复杂度 | 依赖与风险 |
|---|---|---|---|---|---|---|
| P0-1 | 统一状态流转入口，含手动放入洗衣袋 | 解决 H-03、M-01、M-13，让状态与入袋时间只在一处维护 | 新增流转服务，`WearService` 与编辑器改为调用它 | 更容易，Web 版用数据库约束兜底 | 低 | 依赖 C-02 的测试先固定现有行为 |
| P0-2 | 场景缺省策略与失败原因说明 | 解决 H-01 | 生成服务返回结构化的失败原因 | 相同 | 低 | 需要你选择策略，见 D5 |
| P0-3 | 备份格式 v2，导入预检，导入前快照 | 解决 C-01、M-02、M-03，也是迁移通道 | `BackupService` 重写为流式；新增 zip 打包 | Web 版直接实现导入器 | 中 | iOS 端需要 zip 打包能力，系统框架是否满足需要在实现前确认 |
| P0-4 | 缩略图与图片规格化 | 解决 H-04，降低备份体积 | iOS 端可先做内存缓存；Web 端入库即生成 | 明显更容易 | iOS 低，Web 中 | iOS 端若持久化缩略图需要新增字段，依赖 P0-5 |
| P0-5 | Schema 版本化迁移 | 解决 H-05，为后续任何模型变更提供安全通道 | iOS 声明 V1；Web 版迁移文件 | Web 版从第一天就有 | 低 | 声明 V1 不改变现有结构 |
| P0-6 | 测试体系与黄金样本 | 解决 C-02，是移植一致性的唯一依据 | 新增测试目标，生成算法注入随机源 | 样本在 Web 版复用 | 中 | 注意 L-08 的 skip-worktree |

### 9.2 P1 强烈建议

| 编号 | 功能 | 为什么需要与解决的问题 | 对架构的影响 | Web 化后是否更容易 | 复杂度 | 依赖与风险 |
|---|---|---|---|---|---|---|
| P1-1 | 全槽位天气约束 | 解决 H-02，同时修正 M-07 | 生成算法新增规则表 | 相同 | 低 | 规则阈值需要你确认，修改前后用黄金样本对比 |
| P1-2 | 删除确认、软删除与撤销 | 解决 M-09 | iOS 端可只加确认；软删除需要新增字段 | 更容易 | 低到中 | 软删除依赖 P0-5 |
| P1-3 | 本地定时自动备份 | 当前只有手动冷备份 | Web 版任务队列定时执行 | 更容易，iOS 端受后台执行限制 | 低 | 依赖 P0-3 |
| P1-4 | 文本搜索与结果直达编辑 | 解决 M-17，利用已有的名称、品牌、备注字段 | 查询服务 | 更容易，SQLite 支持全文索引 | 低 | 无 |
| P1-5 | 单品穿着次数与最后穿着日期 | `WearRecord.swift:9` 的既定规划，也让吃灰判定更准确 | 统计服务新增聚合 | 更容易，一条 SQL 聚合 | 低 | 不得引入价格字段 |
| P1-6 | 收藏重命名、完整性提示、来源修正 | 解决 H-03 的残缺收藏与 M-05 | `Outfit` 已有 `name` 字段 | 相同 | 低 | 无 |

### 9.3 P2 提升使用体验

| 编号 | 功能 | 为什么需要与解决的问题 | 对架构的影响 | Web 化后是否更容易 | 复杂度 | 依赖与风险 |
|---|---|---|---|---|---|---|
| P2-1 | 差旅模式与返程入洗衣袋 | 解决 M-12 | 生成服务接受可用池参数 | 相同 | 中 | 依赖 P0-1 |
| P2-2 | 月历视图与记录备注 | `CalendarHistoryView.swift:6` 的既定规划，`WearRecord.notes` 已有字段 | 仅界面 | 更容易 | 低 | 无 |
| P2-3 | 用原图重新抠图 | `ClothingItem.swift:37` 的既定用途 | 媒体服务新增任务 | 更容易 | 低 | 依赖原图保留策略 D4 |
| P2-4 | 相似检测按分类、缓存、合并操作 | 解决 M-10 | 新增特征缓存 | 更容易 | 中 | 跨平台分支需重新标定阈值 |
| P2-5 | 颜色命名统一 | 解决 M-16 与 L-01 | 颜色模块 | 相同 | 低 | 已有单品名称是否批量更新需要你决定 |
| P2-6 | 上传时按内容哈希提示重复 | 减少重复录入 | 媒体服务 | 更容易 | 低 | 无 |

### 9.4 P3 以后考虑

| 编号 | 功能 | 为什么需要与解决的问题 | 对架构的影响 | Web 化后是否更容易 | 复杂度 | 依赖与风险 |
|---|---|---|---|---|---|---|
| P3-1 | 自由画布拼搭 | `docs/DEVELOPMENT.zh-CN.md:285` 与 `Outfit.canvasLayoutData` 的既定规划 | 新增画布数据结构 | 浏览器画布能力成熟 | 高 | 依赖 M-06 的槽位设计 |
| P3-2 | 基于画像的衣橱补充建议 | `SettingsView.swift:84` 的既定规划 | 新增规则引擎 | 相同 | 高 | 规则来源需要你提供；不得联网 |
| P3-3 | iOS 与 Web 双向同步 | 两端并存时的需要 | 依赖 API 与冲突合并策略 | 需要先有 Web 版 API | 高 | 依赖 D3 |

---

## 10. Migration Roadmap

### Phase 0 · Audit / Stabilization

目标是在不改变 schema 的前提下，让现有 iOS 版行为正确且可测试，并让数据出口可靠。

| 步骤 | 内容 | 产出 |
|---|---|---|
| 0.1 | 解除 `project.pbxproj` 的 skip-worktree，新增测试目标 | 可运行的空测试目标 |
| 0.2 | 生成算法增加随机源参数，默认值保持系统随机源 | 行为不变的可测版本 |
| 0.3 | 为第 4.2 节中可脱离设备的项目写特征测试与黄金样本 | 测试与 JSON 样本 |
| 0.4 | 修复 H-01、H-03、M-01、M-04、M-05、M-08，每个修复先写失败测试 | 修复与回归测试 |
| 0.5 | 备份导出与导入移出主线程，导入校验版本与枚举，合并时处理活动记录 | C-01 短期修复，M-02 修复 |
| 0.6 | 往返测试验证 M-03 | 测试结论 |
| 0.7 | 用真机导出一份真实 `.wardrobe`，脱敏后作为导入契约 fixture | 契约样本 |
| 0.8 | 建立 CI，至少执行构建与可脱离设备的测试 | 编译门禁 |

### Phase 1 · Architecture preparation

| 步骤 | 内容 | 依赖 |
|---|---|---|
| 1.1 | 声明 `VersionedSchema` V1 与空的迁移计划，容器创建失败进入恢复界面 | Phase 0 |
| 1.2 | 抽取领域核心为独立 Swift 包，只含值类型与纯函数，迁入 M-18 列出的视图规则 | 0.3 |
| 1.3 | 实现统一状态流转服务 P0-1 | 1.2 |
| 1.4 | 定义并实现备份 v2，iOS 端可导出 v2 | 0.5 |
| 1.5 | 做出 D1 至 D5 的决策 | 无 |

### Phase 2 · Backend / API separation

| 步骤 | 内容 | 依赖 |
|---|---|---|
| 2.1 | 按 D1 建立服务端工程，HTTP 层含 Host、Origin 校验与 CSP | 1.5 |
| 2.2 | SQLite schema 与迁移，按第 7.4 节 | 2.1 |
| 2.3 | 领域核心接入，分支 M 直接依赖 1.2 的 Swift 包，分支 X 移植并通过全部黄金样本 | 1.2、0.3 |
| 2.4 | 应用服务与 API，先实现只读接口，再实现写接口 | 2.2、2.3 |
| 2.5 | `.wardrobe` v1 与 v2 导入器，含预检报告 | 0.7、1.4 |

### Phase 3 · Web UI

按依赖顺序实现页面。衣橱只读网格与单品详情先行，随后是单品编辑，再到洗衣房、穿搭三个子页、日历、看板、设置与备份、差旅、相似检测。每个页面上线时同步编写端到端测试。

### Phase 4 · Local file processing integration

| 步骤 | 内容 |
|---|---|
| 4.1 | 上传会话、类型嗅探、像素上限、HEIC 生成可显示版本、元数据剥离 |
| 4.2 | 持久化任务队列与事件流 |
| 4.3 | 抠图、取色、缩略图任务，分支 M 复用 `VisionService`，分支 X 接入本地模型 |
| 4.4 | 批量录入向导，逐文件进度与失败清单 |
| 4.5 | 相似检测任务与特征缓存 |

### Phase 5 · Testing

| 层次 | 内容 |
|---|---|
| 领域 | 黄金样本一致性测试，两端共用同一批 JSON |
| 数据库 | 每个迁移的升级测试，约束测试，含至多一条活动记录与入袋时间约束 |
| API | 每个端点的集成测试，含非法枚举、越权路径、超大上传 |
| 文件系统 | 上传、转码、清理、备份导出与导入往返 |
| 图像 | 固定图片夹具的抠图与取色回归，分支 X 需要人工验收一批真实衣物照片 |
| 端到端 | 浏览器自动化覆盖录入、生成、穿着、脱下、洗衣、备份 |
| 安全 | Host 头伪造、跨源写请求、SVG 上传、路径穿越尝试 |

### Phase 6 · Packaging / local deployment

提供一条命令启动服务并自动打开浏览器，首次启动创建 `DATA_DIR` 并选择空闲端口。升级时先自动备份再执行迁移。是否需要开机自启动、采用哪种分发方式，取决于 D1 与 D6。

### Phase 7 · Final stabilization

用真实 iPhone 数据做正式迁移，iOS 与 Web 并行使用一段时间，对比两端生成结果与统计结果，按真实数据量调优缩略图尺寸与查询，最后完成一次安全复查并更新文档。

---

## 11. Recommended Implementation Order

```text
1. 测试目标与黄金样本                     无依赖
        ↓
2. Phase 0 的缺陷修复                     依赖 1，防止修复引入回归
        ↓
3. 备份出口修复与真实导出 fixture          依赖 1，这是迁移通道
        ↓
4. 你对 D1 至 D6 做出决策                  阻塞服务端技术选型
        ↓
5. Schema 版本化与领域核心抽取             依赖 2，规则先修正再抽取
        ↓
6. 服务端骨架、SQLite schema、导入器        依赖 3、4、5
        ↓
7. 图片处理管线与任务队列                  依赖 6 与 D1
        ↓
8. Web UI，只读页面先行，再到写操作         依赖 6、7
        ↓
9. 端到端测试与一致性测试                  依赖 8
        ↓
10. 本地打包与启动方式                     依赖 9
        ↓
11. 真实数据迁移与双端并行                  依赖 10
```

第 1 步排在最前，原因是之后每一步都要证明没有破坏既有行为。第 2 步排在第 5 步之前，原因是先在原位置修正规则，再把正确的规则抽到领域核心，可以避免把缺陷一起搬走。第 3 步排在服务端之前，原因是导入器的输入格式必须先确定。第 4 步的决策不影响第 1 到第 3 步，可以与它们并行进行。

### 11.1 需要你决定的问题

以下信息在 repository 中不存在，会直接改变架构选择，需要你提供答案。

| 编号 | 问题 | 影响 |
|---|---|---|
| D1 | Web 版是否只需要在 macOS 上运行 | 决定后端语言，以及 Vision 能否复用 |
| D2 | 是否需要用手机浏览器通过局域网访问 | 决定是否需要登录、配对令牌与 HTTPS |
| D3 | iOS 应用是否继续维护，是否需要与 Web 版双向同步 | 决定领域核心是否必须做成共享包，以及备份 v2 是否需要双向兼容 |
| D4 | 原图是否需要长期保留，是否保留原图元数据 | 决定存储占用、隐私处理和重新抠图功能 |
| D5 | 未勾选场景的单品应当被视为适用全部场景，还是保存时强制选择 | 决定 H-01 的修复方式 |
| D6 | 期望的启动方式是终端命令、容器，还是登录后自动在后台运行 | 决定 Phase 6 的打包形态 |
