# Closet Manager 开发文档（详细）

> 一款纯本地、完全离线的 iOS 智能衣橱 App。本文档记录整体架构、数据模型、服务层、核心算法、分阶段开发历程，以及构建部署与 GitHub 工作流。

---

## 目录
1. [设计原则与技术栈](#1-设计原则与技术栈)
2. [整体架构与目录结构](#2-整体架构与目录结构)
3. [数据层（SwiftData 模型与枚举）](#3-数据层)
4. [服务层（业务逻辑）](#4-服务层)
5. [视图层（SwiftUI）](#5-视图层)
6. [核心算法详解](#6-核心算法详解)
7. [状态机与生命周期](#7-状态机与生命周期)
8. [分阶段开发历程](#8-分阶段开发历程)
9. [数据兼容与迁移策略](#9-数据兼容与迁移策略)
10. [构建与真机部署](#10-构建与真机部署)
11. [GitHub 工作流与隐私处理](#11-github-工作流与隐私处理)
12. [已知限制与后续优化](#12-已知限制与后续优化)

---

## 1. 设计原则与技术栈

**硬性原则**
- **纯本地离线**：绝不使用任何联网 API（无网络天气、无外部 AI、无云图床）。所有智能能力均由苹果端侧框架提供。
- **仅原生框架**：SwiftUI、SwiftData、Vision、CoreImage、Swift Charts、PhotosUI。适配 iOS 17+ / macOS 14+。
- **UI / Data / Logic 分离**：视图只负责展示与交互；业务逻辑集中在 `Services/` 与 `ViewModels/`；数据结构集中在 `Models/`。
- **中文注释**：UI 文案、代码注释、交互均为中文；代码标识符用规范英文。

**技术栈**

| 领域 | 框架 |
|---|---|
| UI | SwiftUI |
| 本地持久化 | SwiftData |
| 抠图 / 相似检测 | Vision（`VNGenerateForegroundInstanceMaskRequest`、`VNGenerateImageFeaturePrintRequest`） |
| 取色 / 图像处理 | CoreImage / CoreGraphics / ImageIO |
| 图表 | Swift Charts |
| 相册 | PhotosUI（`PhotosPicker`） |
| 文件 | `.fileImporter` / `.dropDestination` |

---

## 2. 整体架构与目录结构

分层：**Models（数据） → Services / ViewModels（逻辑） → Views（UI）**。SwiftData 通过 `@Query` 让 UI 在数据变更时自动刷新，实现「改状态即刷新」。

```
ClosetManager/
├── App/
│   └── ClosetManagerApp.swift        # @main 入口 + ContentView(TabView) + 全局 tint/外观
├── Models/                           # 纯数据结构
│   ├── ClothingItem.swift            # 单品实体（@Model）
│   ├── Outfit.swift                  # 穿搭实体（@Model）
│   ├── WearRecord.swift              # 穿搭日历记录（@Model）
│   ├── ClosetSchema.swift            # Schema + ModelContainer 配置
│   ├── ImageSource.swift             # 统一图片来源（相册/文件/拖拽）
│   ├── Support/StoredColor.swift     # 颜色持久化结构体
│   └── Enums/                        # 全部枚举
├── Services/                         # 无 UI 的业务逻辑
│   ├── VisionService.swift           # 抠图 + 取色（actor）
│   ├── OutfitGeneratorService.swift  # 叠穿生成引擎（纯函数）
│   ├── WearService.swift             # 穿着/脱下/洗衣/行李流转
│   ├── DuplicationDetectorService.swift # 相似单品检测（actor）
│   ├── AnalyticsService.swift        # 看板统计
│   ├── TravelService.swift           # 差旅携带计算
│   └── BackupService.swift           # 本地冷备份导入导出
├── ViewModels/
│   └── ItemDraftModel.swift          # 录入/编辑草稿（@Observable，单件与批量共用）
└── Views/
    ├── WardrobeGalleryView.swift     # 衣橱主页
    ├── LaundryView.swift             # 洗衣房
    ├── CalendarHistoryView.swift     # 日历
    ├── ItemEditorView.swift          # 单件录入/编辑
    ├── BatchImportView.swift         # 批量序列化编辑器
    ├── SettingsView.swift            # 设置（画像/外观/工具/备份）
    ├── TravelCapsuleView.swift       # 差旅打包
    ├── WardrobeSearchView.swift      # 高级交叉筛选
    ├── DuplicationView.swift         # 清理相似衣物
    ├── Outfit/                       # 穿搭生成/收藏/自由拼搭/脱下弹窗
    ├── Analytics/                    # 看板 + 热力图 + 树形图
    └── Components/                   # 复用组件（卡片/缩略图/表单区块/胶囊/流式布局等）
```

---

## 3. 数据层

### 3.1 三个 @Model 实体与关系

| 关系 | 类型 | 说明 |
|---|---|---|
| `ClothingItem` ↔ `Outfit` | 多对多 | 一件单品可被多套穿搭复用；反向关系声明在 `Outfit.items` |
| `ClothingItem` ↔ `WearRecord` | 多对多 | 某天穿了哪些单品；反向关系声明在 `WearRecord.items` |
| `Outfit` ↔ `WearRecord` | 一对多 | 一套穿搭可被多次穿着记录；反向关系声明在 `Outfit.wearRecords` |

删除规则统一 `.nullify`（删单品不连带删穿搭/记录）。每对关系的 `inverse` 只在一侧声明——SwiftData 最稳健写法。

**ClothingItem（核心字段）**
- 基本：`name`、`category`、`subtype?`、`scenarios[]`、`status`
- 属性：`isWaterproof`、`warmthScore`(1–100)、`warmthLevels[]`（由分数派生）、`seasons[]`
- 图像：`processedImageData`（抠图去背，`.externalStorage`）、`originalImageData`（原图）
- 颜色：`dominantColor`/`secondaryColor`（`StoredColor`）、`dominantColorCategory`（落库色桶，便于聚合）
- 洗衣：`laundryEntryDate?`（入袋时间，用于滞留预警）
- 便捷方法：`defaultName(color:subtype:category:)`、`isAvailable`、`isSuitable(forWarmth/forScenario)`、`refreshColorCategory()`

**Outfit**：`isFavorite`、`source`、`targetScenario?`、`targetWarmthLevel?`、`items[]`；计算槽位 `outerwear/top/bottom/shoes/accessories/socks`、`missingRequiredSlots`、`isStructurallyValid`（必选：上装+下装+鞋子）。

**WearRecord**：`date`、`isActive`（是否「目前正在穿」，至多一条为 true）、`outfit?`、`items[]`。

### 3.2 枚举清单

| 枚举 | 取值 | 关键能力 |
|---|---|---|
| `Category` | 外套/上装/下装/鞋子/配饰/袜子 | `isRequiredInOutfit`、`washByDefaultOnTakeOff`、`subtypes` |
| `Subtype` | ~40 个二级子类（含西装 suit、羽绒 downJacket、拖鞋 slippers） | `category` 归属、`displayName` |
| `Scenario` | 通勤/休闲/运动/正式 | `conflictingScenarios`（正式⨯运动） |
| `ItemStatus` | 在衣橱/在洗衣袋/在行李箱 | 仅 `inWardrobe` 参与生成 |
| `WarmthLevel` | 严寒→炎热 6 档 | `from(score:)`、`torsoBudget`、`maxSingleGarmentWarmth`、`seasons` |
| `Season` | 春夏秋冬 | `derive(from: warmthLevels)` |
| `ColorCategory` | 14 个粗色桶 | `classify(_:)`（HSB 归类，看板聚合用） |
| `ColorNaming` | ~30 具名色（藏青/酒红…） | `name(for:)` 最近邻精细命名 |
| `GalleryItemSize` | 大/中/小 | `columns`、`showsLabels` |
| `AccentChoice` / `AppearanceMode` | 强调色 / 外观模式 | 根视图 `.tint` / `.preferredColorScheme` |
| `ImageSource` | `.photo` / `.data` | 归一相册/文件/拖拽三种录入来源 |

**StoredColor**：`Codable` 结构体（sRGB 0…1 分量），跨平台不依赖 UIColor/NSColor；提供 `color`(SwiftUI)、`hexString`、`hsb`、`refinedColorName`。

---

## 4. 服务层

### VisionService（`actor`）
- `removeBackground(from:) async throws -> Data`：本地抠图，输出带透明通道 PNG。
- `extractColors(from:) async -> (dominant, secondary)`：CoreImage 取主辅色。
- 全部基于跨平台 `CGImage`/ImageIO，处理 EXIF 方向；模拟器失败时给「建议真机」提示。

### OutfitGeneratorService（`enum`，纯函数）
- `generate(from:warmth:scenario:requireWaterproof:maxCount:) -> Result`。
- 产出 `OutfitDraft`（`top` + `midLayer?` + `bottom` + `shoes` + `outerwear?` + `accessory?` + `socks?`），核心是**保暖度求和匹配气温**的叠穿构建 `buildTorso`。详见 [第 6 节](#6-核心算法详解)。

### WearService（`enum`）
穿搭生命周期与流转，全部作用于传入的 `ModelContext`（`@Query` 自动刷新）：
- `addToFavorites` / `wearToday` / `wearOutfit` / `deactivateActiveRecords`
- `takeOff(_:laundryItems:)`：勾选进洗衣袋（写 `laundryEntryDate`），未勾选回衣橱
- `returnToWardrobe`（洗净放回，清 `laundryEntryDate`）
- `packIntoLuggage` / `unpackAllLuggage`（差旅装箱/取出）

### DuplicationDetectorService（`actor`）
- `findSimilarGroups(_:featureThreshold:colorThreshold:) -> [[UUID]]`：Vision 特征指纹 + 主色距离 + 并查集聚类。**不跨 actor 传 @Model**，用 Sendable 的 `ItemFingerprintInput`（id/imageData/color）进、`[[UUID]]` 出。

### AnalyticsService（`enum`）
`inventoryByCategory` / `colorInventory` / `colorFrequency` / `dailyActivity`。**刻意不含任何价格 / 成本 / CPW 字段。**

### TravelService（`enum`）
内裤/袜子携带量：`min(天数 + 1, 5)`（每天 1 条 + 1 备用，封顶 5）；`showsCapHint(days) = days > 4`。

### BackupService（`enum`）
Codable DTO（图片 base64 内联）→ 导出 `.wardrobe`（JSON）供 `ShareLink` 分享；`restore(from:mode:)` 支持**覆盖 / 合并**，按 id 重建关系。

### ItemDraftModel（`@Observable`，ViewModels）
单件编辑与批量录入**共用**的草稿对象：持有全部可编辑字段 + 图像/颜色 + 处理状态；`process(source:/_:/data:)` 统一走 `ingest`（存原图 → 抠图 → 取色）；`makeNewItem()` / `apply(to:)` 落库。

---

## 5. 视图层

**底部 5 个 Tab**（`ContentView` 的 `TabView`）：衣橱 · 洗衣房 · 穿搭 · 日历 · 看板。根视图套 `.tint(强调色)` 与 `.preferredColorScheme(外观)`。

- **衣橱** `WardrobeGalleryView`：顶部「目前正在穿」看板、分类过滤、**洗衣袋/行李箱隔离**、大中小动态网格、齿轮（设置）/漏斗（高级筛选）/＋（单件·从相册批量·从文件批量）入口、**拖拽释放**导入。
- **洗衣房** `LaundryView`：筛 `inLaundry`，勾选「洗净放回」，滞留 >4 天红色预警。
- **穿搭** `OutfitHomeView`：分段「智能生成 / 收藏夹 / 自由拼搭」。生成页 `OutfitGeneratorView` 有温度/场景/雨雪开关 + 横滑卡片；`TakeOffSheet` 承载脱下流转。
- **日历** `CalendarHistoryView`：按日期倒序的穿搭历史。
- **看板** `AnalyticsDashboardView`：库存条形图、颜色树形图、色彩偏好、活跃度热力图。
- **录入**：`ItemEditorView`（单件）与 `BatchImportView`（批量）都渲染复用的 `ItemFormSections` + `ItemDraftModel`。
- **设置** `SettingsView`：个人资料、外观自定义（强调色/外观/圆角）、工具（差旅打包 / 清理相似衣物）、数据冷备份。

---

## 6. 核心算法详解

### 6.1 本地抠图（VisionService）
```
原图 Data → CGImage（读 EXIF 方向）
→ VNImageRequestHandler.perform([VNGenerateForegroundInstanceMaskRequest])
→ observation.generateMaskedImage(ofInstances: allInstances, from: handler, croppedToInstancesExtent: true)
→ CVPixelBuffer(RGBA) → CIImage → CGImage → PNG（保留 Alpha）
```
裁剪到主体外接框，得到干净的卡片图；失败回退原图、仍可保存。

### 6.2 主辅色提取
缩放到 48×48 RGBA → 每通道量化到 6 档（6×6×6=216 桶）→ 跳过 alpha<32 的透明背景像素 → 按出现次数排序：**主色 = 最大桶均值**；**辅色 = 第一个与主色 RGB 曼哈顿距离 > 0.25 的桶**。在透明背景图上做，背景不干扰。

### 6.3 叠穿引擎（重构核心）
每件单品有 `warmthScore`(1–100)；每个天气档位有：
- `torsoBudget`：目标躯干保暖总和（炎热 22 … 严寒 170）
- `maxSingleGarmentWarmth`：**气温向下兼容**——炎热天允许的单件上限（羽绒被排除；短袖可在严寒作最内层打底）

`buildTorso` 逻辑：
1. `base` = 「不超预算的最暖上装」（favor 少层：温和天卫衣可单穿）
2. 不够暖 → 加中层（更暖的另一件上装，且**同类排斥**：base 与中层不同为短袖）
3. 仍不够 / 雨雪天强制 → 加外套（**基础打底**：外套始终建立在上装之上，绝不单穿）
4. 约束：`scenario==.sport` 排除西装/西装外套（**场景纯净**）；拖鞋绝不入选；`requireWaterproof` 时外套与鞋子必须防水且外套必选。

### 6.4 相似单品检测
逐件 `VNGenerateImageFeaturePrintRequest` 得特征指纹 → 两两 `computeDistance`（越小越像）；**当特征距离 < 0.6 且主色距离 < 0.30** 判为相似 → 并查集聚成组（≥2 件）。仅手动触发（设置页），`actor` 后台执行。阈值为经验值，需真实衣橱微调。

### 6.5 颜色树形图 & 活跃度热力图
- **树形图**：递归二分切割（slice-and-dice），色块面积 ∝ 件数、填充即对应色、文字按背景明暗选黑/白保证对比。
- **热力图**：最近 16 周，`LazyHGrid` 7 行（星期）× 列（周），单元格深浅表当天打卡次数（GitHub 贡献图风格）。

---

## 7. 状态机与生命周期

```
[穿搭草稿] ──今天穿这套──▶ WearRecord(isActive=true) ──▶ 衣橱顶部「目前正在穿」看板
                                    │
                        脱下并扔进洗衣袋（TakeOffSheet）
                                    ▼
   一键全扔：全部 → inLaundry（写 laundryEntryDate）
   按勾选脱下：勾选→inLaundry（写时间），未勾选→inWardrobe
                                    ▼
        isActive=false（转日历历史） + 单品流入洗衣房
                                    ▼
        洗衣房「洗净放回」 → inWardrobe（清 laundryEntryDate）

差旅：装箱 → inLuggage（与日常算法隔离）；结束差旅 → 全部回 inWardrobe
```
`ItemStatus` 三态中**仅 `inWardrobe` 参与穿搭生成**；`inLaundry`/`inLuggage` 均从衣橱主网格隔离（洗衣袋可用开关放出，行李箱始终隐藏）。

---

## 8. 分阶段开发历程

| 阶段 | 内容 |
|---|---|
| 一 | SwiftData 数据模型：三实体 + 全部枚举 + 关系设计 |
| 二 | 单件录入 UI + Vision 本地抠图链路（PhotosPicker → 去背 → 存取） |
| 三 | 穿搭生成引擎、洗衣袋流转状态机、「目前正在穿」看板、日历记录 |
| 四 | 子类体系、批量录入向导、洗衣袋隔离、大中小动态网格、相似检测、设置页 |
| 五 | CoreImage 取色与精细色名、卡片零遮挡主色、保暖度叠穿引擎、Swift Charts 看板、ColorPicker 吸管 |
| 六 | 防水属性 + 雨雪强关联、滞留预警、差旅打包、高级交叉筛选、外观自定义、颜色树形图、本地冷备份 |
| 七 | 文件系统导入（`.fileImporter` + 安全沙盒）、原生拖拽（`.dropDestination`），统一汇入批量编辑器 |

**关键设计决策**：温度用「保暖度」而非具体度数；分类互斥 + 二级子类；命名「颜色+子类」自动生成；洗衣「智能默认」而非硬锁；相似检测手动触发不卡上传。

---

## 9. 数据兼容与迁移策略

所有跨阶段新增字段都是**「带默认值的加项」**（`subtype?`、`isActive=false`、`warmthScore=50`、`isWaterproof=false`、`laundryEntryDate?`、`inLuggage` 枚举 case），SwiftData 走**轻量迁移**，老数据可直接升级、无需删 App。

`@Model` 的 `init` 内**不要读 `self.属性`**（宏把属性访问变成带后备存储的 getter，会「在初始化完成前访问 self」报错）——统一用本地常量再赋值（见 `ClothingItem.init` 的 `resolvedLevels`）。

---

## 10. 构建与真机部署

- **环境**：Xcode 26+ / iOS 17+，工程用 Xcode 16 文件系统同步分组（新增 Swift 文件不改 `.pbxproj`）。
- **默认并发隔离**：`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`（避免 SwiftData 复合属性 Codable 的主线程隔离告警）。
- **真机签名**：`Signing & Capabilities` → 勾 Automatically manage signing → 选自己的 Team → Bundle ID 唯一。
- **设备**：iPhone 开「开发者模式」并信任电脑；首次安装需在「VPN与设备管理」信任开发者证书。
- **有效期**：免费 Apple ID 签名 7 天过期（最多 3 个自签 App）；付费开发者账号 1 年。
- **测试重点**：Vision 抠图/特征指纹在**真机**才稳定（模拟器常失败）。

---

## 11. GitHub 工作流与隐私处理

- 仓库：`https://github.com/KentaiC/ClosetManager`（公开）。README 双语：`README.md` 英文为主 + `README.zh-CN.md`，顶部互链。
- **邮箱匿名化**：本仓库 git 邮箱用 `KentaiC@users.noreply.github.com`，历史已重写，不含真实 Gmail。
- **团队 ID 隔离**：`.pbxproj` 里 `DEVELOPMENT_TEAM` 在仓库中保持为 `""`；已 `git update-index --skip-worktree` 让 git **永久忽略**本地对该文件的改动——本地保留团队 ID 以便真机构建，但永不进公开仓库。若将来确需提交 `.pbxproj` 的合法改动，先 `--no-skip-worktree`。
- **日常更新**：改完代码即「提交 + `git push`」。

---

## 12. 已知限制与后续优化

- **模拟器**：Vision 抠图 / 特征指纹常失败，需真机验证。
- **图片解码性能**：网格每个 cell 每次渲染都把整张 `Data → Image` 解码；单品极多时可能卡顿。抠图结果已裁剪较小；后续可加缩略图缓存。
- **相似检测阈值**：`featureThreshold=0.6 / colorThreshold=0.30` 为经验初值，需按真实衣橱微调；特征指纹距离无固定上界。
- **备份体积**：`.wardrobe` 以 base64 内联图片，衣物多时文件较大；后续可改为 zip 打包。
- **自由拼搭**：当前为「按槽位选单品」，尚非拖拽自由画布（`Outfit.canvasLayoutData` 已预留）。
- **用户画像**：身高/体重/性别已存（@AppStorage），尚未接入「衣橱补充智能建议」。
