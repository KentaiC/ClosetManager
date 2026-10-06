# 本地 Web 版使用指南

本地 Web 版在你自己的电脑上运行一个只对本机开放的服务，用浏览器使用衣橱的全部功能。数据保存在本机，不连接任何网络服务。iOS App 继续可用，两边通过 `.wardrobe` 备份文件交换数据。

## 运行要求

| 项目 | 要求 |
|---|---|
| 系统 | macOS 14 或更新版本。抠图、自动取色、HEIC 转换与相似检测依赖 macOS 的 Vision 与 ImageIO |
| Swift | 支持 swift-tools-version 6.0 的工具链。安装 Xcode 或 Xcode 命令行工具即可 |
| Node.js | 22，用于构建前端。CI 使用的也是这个版本 |
| 浏览器 | 任一主流浏览器 |

服务端也能在 Linux 上运行，但没有图片处理能力：上传的图片会经过格式与尺寸校验后保存，不做抠图与取色，主色需要在表单中手动选择，HEIC 图片在多数浏览器中无法显示，相似检测不可用。

## 第一次运行

在仓库根目录执行：

```bash
scripts/closet
```

脚本会安装前端依赖并构建前端，以 release 模式构建服务端，然后启动服务并在默认浏览器中打开 `http://127.0.0.1:8765/`。第一次构建耗时较长，之后只在源文件有改动时重新构建。

终端中出现「Closet Manager 已启动」即可使用。按 Ctrl-C 停止服务。

## 把 App 中的数据搬过来

在 iOS App 的设置页选择「生成备份文件」，再通过分享把 `.wardrobe` 文件存到这台电脑上。然后任选一种方式导入。

在浏览器中打开设置页，选择「导入备份」，选好文件后选择「与现有数据合并」或「覆盖现有数据」。页面会先显示预检报告，确认后才写入。

也可以在终端中导入。不加 `--apply` 时只输出预检报告：

```bash
scripts/closet import ~/Downloads/ClosetBackup-xxxx.wardrobe
scripts/closet import ~/Downloads/ClosetBackup-xxxx.wardrobe --apply
scripts/closet import ~/Downloads/ClosetBackup-xxxx.wardrobe --mode overwrite --apply
```

服务端对备份文件的校验比 App 严格。遇到无法识别的取值时，整个文件不会导入，报告会指出具体位置。导出的备份文件与 App 的格式相同，可以再导入 App。

## 端口与地址

默认端口是 8765。没有指定端口且 8765 被占用时，服务会依次尝试 8766 到 8774，并在终端中提示实际地址。界面偏好按浏览器地址分别保存，换了端口需要重新设置一次。

指定端口：

```bash
scripts/closet --port 9000
```

指定的端口被占用时服务不会自动换端口，而是报错退出。

## 数据位置

数据默认保存在 `~/Library/Application Support/ClosetManager`。在 Linux 上是 `$XDG_DATA_HOME/ClosetManager` 或 `~/.local/share/ClosetManager`。用 `--data-dir` 可以指定其它位置：

```bash
scripts/closet --data-dir ~/Documents/ClosetData
```

| 位置 | 内容 |
|---|---|
| `closet.sqlite` | 单品、穿搭、穿着记录与设置 |
| `media/` | 图片文件，按内容哈希命名 |
| `backups/pre-migration/` | 数据库结构升级前自动保存的数据库副本 |
| `backups/before-import/` | 每次导入备份前自动导出的当前数据，保留最近五份 |
| `tmp/` | 临时文件 |

日常备份可以在设置页选择「生成并下载备份文件」。备份是单个 `.wardrobe` 文件，包含全部图片。

## 升级

拉取新代码后照常运行 `scripts/closet`，脚本会重新构建。数据库结构需要升级时，服务会先把数据库复制到 `backups/pre-migration`，再执行升级。

## 安全

服务只监听 127.0.0.1，同一网络中的其它设备无法访问。服务会拒绝 Host 不是本机地址的请求，写操作只接受本服务自己页面发出的请求，所以其它网站不能读取或修改你的数据。请不要通过端口转发或反向代理把服务暴露到网络上。

## 常见问题

| 现象 | 处理方式 |
|---|---|
| 提示需要 Node.js | 安装 Node.js 22 后重新运行 |
| 提示需要 Swift 工具链 | 安装 Xcode 或执行 `xcode-select --install` |
| 提示端口已被占用 | 换一个端口，或先停止占用该端口的程序 |
| 浏览器没有自动打开 | 手动访问终端中显示的地址 |
| 页面显示「当前服务不支持本地抠图」 | 服务运行在没有 Vision 的平台上，请在 macOS 上运行 |
| 页面只显示接口错误、没有界面 | 前端尚未构建。运行 `scripts/closet` 会自动构建，或在 Web 目录执行 `npm ci && npm run build` |
