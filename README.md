**中文** | [English](README_EN.md)

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="Mistake Notebook · 错题本"></p>

# Mistake Notebook · 错题本

**整理自己的错题，留给下一次更有把握的作答。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) [![App Store](https://img.shields.io/badge/App%20Store-已上架-0D84FF?logo=apple)](https://apps.apple.com/app/id6806626967) ![License](https://img.shields.io/badge/License-MIT-green)

从自己的试卷与错题照片开始，把零散的学习资料整理起来，方便持续复习。新账号和公开安装包都是空白个人错题本，学习资料与记录按账号隔离。

三个入口是错题本、导入、复习，账号、提醒和离线管理位于右上角设置。iPhone / iPad 使用普通相机拍照或从相册选择图片，Mac 选择图片文件；确认上传后由共用学习库服务识别。练习和复习使用自己的题目，不承诺每道题都有同类变式。


## 它做什么

| 功能 | 说明 |
|---|---|
| **自己的错题，自己整理** | 导入自己的错题照片，建立个人学习资料。新账号从空白开始。 |
| **下载自己的练习，离线复习** | 登录后同步本人资料，下载好的练习可以离线使用；不同账号的学习记录分别保存。 |
| **拍照或选择图片后导入** | 手机和平板可拍照或从相册选图，Mac 可选择图片文件。上传前确认学科、页码及 AI 识别说明，逐页上传并查看识别结果。每账号前 10 张免费，之后可选择 Apple 月订阅或年订阅继续识别，无需邀请码或 API 密钥。 |

## 一个 App，五个平台

同一个名字、同一个图标、同一个学习库：iPhone、iPad、Mac、Apple Vision Pro 是同一个 target，Apple Watch 是随 iPhone 包一起装的手表 App。错题和进度都在服务端，哪台设备上做的题，别的设备同步后就看到。

| 平台 | 长什么样 | 现在能不能装 |
|---|---|---|
| iPhone | 三个标签页（错题本 / 复习 / 导入），拍照或选图导入 | [App Store](https://apps.apple.com/app/id6806626967) 已上架 |
| iPad | 宽屏：侧栏（错题本 / 复习 / 导入 + 今天的进度）+ 错题列表 + 题目并排；分屏窄栏退回 iPhone 布局 | 在售的是同一个包，但**这套宽屏布局还没发版** |
| Mac | 原生 macOS 窗口，同样的三栏；用文件对话框选图导入；包里自带 `mistakes` 命令行 | **未上架**，只能本机构建 |
| Apple Watch | 抬腕看待巩固几类、今天几题、连续几天，翻一页是先复习哪几类；表盘复杂功能四种。只读，不做题、不导入；登录态由 iPhone 递过来 | **未上架**（随 iPhone 包嵌入的手表 App 还没进任何发行构建） |
| Apple Vision Pro | 同一套三栏放在系统玻璃窗口里；没有相机，用文件选图导入 | **未上架**，只在模拟器上验过 |

<table><tr>
<td align="center" width="50%"><img src="docs/screenshots/07-ipad.png" alt="iPad 横屏：侧栏 + 错题列表 + 题目并排"><br><sub>iPad 横屏：侧栏 + 错题列表 + 题目并排（模拟器截图）</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/08-mac.png" alt="Mac：错题列表与题目并排"><br><sub>Mac：错题列表与题目并排（本机静默离屏截图，侧栏已裁去：离屏渲染画不出选中行的系统材质）</sub></td>
</tr><tr>
<td align="center" width="50%"><img src="docs/screenshots/10-vision.png" alt="Apple Vision Pro：玻璃窗口里的错题本"><br><sub>Apple Vision Pro：玻璃窗口里的错题本（模拟器截图，已裁边）</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/09-watch.png" width="208" alt="Apple Watch：待巩固几类、今天几题、连续几天"><br><sub>Apple Watch：待巩固几类、今天几题、连续几天（模拟器截图）</sub></td>
</tr></table>

截图里的账号「小林」、五份练习和错题记录都是演示数据（`scripts/demo/fixture.py` 在本机临时起的虚构学习库），不是任何真实学生的记录。

### 各平台资源占用（模拟器与本机实测）

<!-- platforms:start -->
| 平台 | 测量环境 | 包体（zip） | 空闲内存 | 空闲 CPU | 冷启动到首屏有数据 | 测量时负载（1 / 5 / 15 分钟） | 目标 |
|---|---|---|---|---|---|---|---|
| iPhone | 未测 | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| iPad | 未测 | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| Mac | 未测 | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| Apple Watch | 未测 | — | — | — | — | — | ≤ 25 MB · ≤ 10 MB 包 · ≤ 1.5 s |
| Apple Vision Pro | 未测 | — | — | — | — | — | ≤ 60 MB |

<sub> 实测，数据来自 `perf/platforms/<平台>.json`。iPhone / iPad / Watch / Vision 是 Xcode 模拟器上的 Release 构建，Mac 是本机原生的本地 Release 构建；**都不是真机数值，包体也不是 App Store 切片**（App Store 的 iPhone 体积见下方「资源占用」）。内存为 App 进程 phys_footprint，CPU 为启动静置 45 秒后 60 秒窗口内的 CPU 时间 ÷ 墙钟，冷启动是发出启动到 App 打出「第一屏有数据」日志的中位数（虚构的本地演示学习库，5 次，丢弃装机后第一次）。模拟器的启动时间随宿主负载浮动很大：2026-10-02 本机内存吃紧时，成长小金库同一份代码的 iPhone 线在不同时段测出 1.8–4.1 秒；Vision Pro 的冷启动里模拟器自己的开销（进程拉起、visionOS 场景初始化）占大头，宿主忙时会明显拉长。</sub>
<!-- platforms:end -->

## 怎么拿到

已在 [App Store](https://apps.apple.com/app/id6806626967) 上架：1.0（build 18）自 2026-09-15 起在售，见[发行记录](perf/asc-release.json)。

公开包不附带个人课程或题库；练习材料由用户自行导入，sync-lessons.sh 只维持零课程公开包。

## 给 Agent 的命令行 · `mistakes`

App 给人用，命令行给 Agent 用。`cli/mistakes` 是同一个服务端（`edu.tianli.cyou` 的 `/api/*`，App 与网页用的同一套接口）的薄客户端，只用 Python 标准库；上传大小、识别额度、订阅、账号归属和注销冻结全在服务端判，读图与生成练习由服务器上的同一个识别工人完成。

本机构建的 Mac 版自带这个命令：`错题本.app/Contents/Resources/bin/mistakes`（`project.yml` 的构建阶段只在 macOS 的 build 里拷进去，随包签名）；iPhone/iPad 包和任何归档（App Store / TestFlight）都不带。

```bash
sh cli/install.sh          # 装了 Mac 版：按 bundle id 找到 .app，链到包里的命令；没装：链到本仓 cli/mistakes（改源码即生效）
sh cli/install.sh --check  # 只核对；--uninstall 只删本产品入口的链接
```

已装的 Mac 版是加这一步之前的旧构建时，`install.sh` 拒绝并提示先重装 Mac 版，不回落到仓库。

凭据只从环境变量或 stdin 取，不落盘、不回显：`EDU_USER`（邮箱或用户名）、`EDU_PASSWORD`（或 `--password-stdin`）；`EDU_API_BASE` 默认 `https://edu.tianli.cyou`。

```bash
mistakes status --json                         # 识别额度/订阅、待录入照片与卷子、识别中作业、注销状态
mistakes wrongs --subject math --json          # 错题本（服务器上的学习存档快照，按课分组）
mistakes progress --json                       # 今天做了几题、目标、经验、连续天数
mistakes import p1.jpg p2.jpg --year 2026 --term 1 --grade 3 --subject math --kind final --consent-ai --wait 120
mistakes job <作业号> --wait 60 --json
mistakes delete upload <照片 id> --yes
```

读命令都支持 `--json`，输出 `{"ok": true, …}`；失败输出 `{"ok": false, "err": …}` 且退出码非 0（1 = 服务端拒绝、网络失败或作业失败，2 = 用法错或缺凭据）。读命令不改任何状态。会把图片发给 AI 识别、占用识别额度的命令（`upload`、`import`、`recognize --kind auto|draft`）必须带 `--consent-ai`，同 App 的识别同意；删除和注销必须 `--yes`。

| App 里能做的 | 命令 |
|---|---|
| 设置里的账号、AI 识别额度与订阅状态、注销进度 | `mistakes status` / `mistakes account deletion-status [--receipt 回执]` |
| 错题本 / 复习（按课、按科目、搜索） | `mistakes wrongs [--subject] [--search]` |
| 今日任务、经验、连续天数 | `mistakes progress` |
| 个人课程包清单 / 下载一课 | `mistakes lessons` / `mistakes lesson <slug> --out 文件` |
| 导入整卷（逐页上传、自动识别） | `mistakes import <图片…> --slug 或 --year --term --grade --subject --kind` |
| 单张错题照片、派识别或入个人课程包 | `mistakes upload` / `mistakes recognize <照片 id> --kind auto\|draft\|commit` |
| 上传记录与作业进度 | `mistakes uploads` / `mistakes papers` / `mistakes job <作业号> [--wait 秒]` |
| 查看上传的原图 / 卷子某页 | `mistakes image upload <照片 id>` / `mistakes image paper <编号> --page N` |
| 删除上传 | `mistakes delete upload\|paper <id> --yes` |
| 注销账号（先即时删除，有扫描记录时转为注销申请） | `mistakes account delete --yes` |

说明：`wrongs` 与 `progress` 读的是服务器上的学习存档快照（设备联网时由练习页同步，后写覆盖），设备离线期间做的题要等下次同步后才看得到；App 的错题本还会显示课程包里的原题行，命令行只列存档里的错题类型。

留在 App 的（纯界面或只在设备上）：拍照与相册选择、页面预览、答题练习本身、每日提醒、离线课程副本、Apple 订阅的购买与恢复（服务端只认 Apple 签名的交易）。

回归：`python3 Tests/cli_mistakes_test.py` —— 先核打包规则与 `install.sh`（临时 Applications 目录里的假 .app），再起一个隔离的本地服务端（临时目录 + 空闲端口），不碰线上账号、不调 AI；需要同一工作区的 `edu/web/points/server.py`，或用 `EDU_SERVER_PY` 指过去。

## 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme WrongBook -destination 'generic/platform=iOS Simulator' build
```

- 仓里的 `*.sh` 是作者本机舰队脚本的 shim（三平台构建 / 真机装机 / TestFlight），依赖 `~/Dev` 下的总部工具，不在本仓；没有那套工具时它们会明确退出。
- `Shared/PlatformCompat.swift` 是总部共享文件的逐字节副本（iOS-only SwiftUI 修饰符在 macOS 侧的同名 no-op），别在这里改它。
- `project.yml` 的 preBuildScripts 会跑 `sync-lessons.sh`，生成并校验零课程的空白个人清单，不访问作者的私人内容库。

开发细节（回归、验证通道、约束）见 [DEVELOPING.md](DEVELOPING.md)。

## 相关

- 产品页：<https://apps.tianli.cyou/p/wrong-book-ios.html>
- 舰队总览（10 个 app 怎么来的）：<https://apps.tianli.cyou/ios.html>
- 教程：[从零到 TestFlight：一个人做 iPhone app 的完整路径](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 曾田力 (Tianli Zeng)

<!-- lightweight:start -->
## 资源占用

安装包为 App Store 数据；内存、CPU 与启动时间为 iOS 模拟器实测，不是真机数值。

| 安装包 | 空闲内存 | 空闲 CPU | 模拟器冷启动到有数据的首屏 |
|---|---|---|---|
| **2.2 MB**（装好后 3.0 MB） | **38.8 MB** | **0.02%** | **3.0 s** |

体积按具体发行构建回读；真机尚未测量，内存、CPU 与启动时间先用 iOS 模拟器实测并标明环境。

<sub>v1.0 (18) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · App Store；体积不含用户数据与后续缓存；手机实际安装版本尚未核验 · 2026-09-26。体积来自 Apple App Store Connect 对应构建的设备切片记录。内存、CPU 与启动时间是 iPhone 17 Pro (iPhone-17-Pro) / iOS 27.0 Simulator 上本地源码 Release 构建 v1.0.1 (19) 的实测（2026-10-04），只统计 App 进程，不等于真机数值；真机测量尚未完成。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->


## 配置与 App 更新

新构建在主界面下方提供「配置与更新」，显示当前安装包的真实版本和构建号。

可选择「使用 iCloud 记住配置」，默认关闭，同步每日提醒的开关和时刻；配置可独立导出为 JSON，再从 Files 导入。恢复后重新计算本机提醒，不自动申请通知权限。学习资料仍走原账号同步。

「检查更新」读取本 App 的 App Store 发行版本；可前往系统商店页面升级，网络失败会显示原因。 此入口检查 App 版本，资料或后台数据刷新仍在原入口。

Mac 沙盒版通过本人 iCloud Drive 中的私有发行包检查更新。首次在「选择 iCloud Drive 更新目录」中选择系统 iCloud Drive 根目录；此目录授权只保存在本机。只有实际发布的发行记录才会出现安装包入口；打开校验后的 ZIP，将其中的 App 放入应用程序文件夹完成升级。

版本号更新属于本轮新构建；手机上的新版本需通过签名安装或原商店/TestFlight 渠道取得，发行状态以现有发布记录为准。

Mac 沙盒版通过已签名授权的系统 KVS 同步同一配置白名单；目录书签、本机权限与更新包不属于同步配置。
