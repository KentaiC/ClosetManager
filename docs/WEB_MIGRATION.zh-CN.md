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
| R2 | 行为缺陷修复单独成轨，不混入迁移阶段 | 迁移要求保持现有功能与数据含义。审计报告中的 H-01、H-02、H-03、M-01、M-04、M-05、M-07 等问题保持现状，已有特征测试的会在修复时显式改变断言。修复放在共享核心中进行，App 与 Web 同时生效 |
| R3 | 审计报告 Phase 0 中的「测试与 CI」提前到第一阶段完成 | 后续每一步都需要回归基线 |

## 5. 阶段进度

### 第一阶段 Architecture preparation

| 提交 | 内容 |
|---|---|
| `ci: add iOS app build check on macOS runners` | 在未改动的代码上建立 iOS 编译基线 |
| `refactor(core): move platform-independent domain files into ClosetManager/Core` | 纯文件移动 |
| `refactor(core): expose shared domain as the ClosetCore Swift package` | 公开访问级别、拆分 SwiftUI 桥接、`Package.swift`、特征测试、CI 中的 SwiftPM 测试 |
| `refactor(core): share outfit generation and analytics through ClosetCore` | 泛型生成引擎与统计、App 侧适配、引擎测试 |

验证结果。Linux 上 `swift test` 共 43 个测试全部通过。替代验证环境中，重构前后生成器在 19,200 次调用下输出逐项一致，统计输出一致，视图层调用表达式通过类型检查。iOS 工程在 Apple 工具链上的编译尚未验证，原因见 R1。
