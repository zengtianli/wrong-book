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

| 安装包 | 空闲内存 | 空闲 CPU | 模拟器冷启动到首屏就绪 |
|---|---|---|---|
| **2.2 MB**（装好后 3.0 MB） | **24.1 MB** | **0.02%** | **1.4 s** |

体积按具体发行构建回读；真机尚未测量，内存、CPU 与启动时间先用 iOS 模拟器实测并标明环境。

<sub>v1.0 (18) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · App Store；体积不含用户数据与后续缓存；手机实际安装版本尚未核验 · 2026-09-26。体积来自 Apple App Store Connect 对应构建的设备切片记录。内存、CPU 与启动时间是 iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 上本地源码 Release 构建 v1.0 (11) 的实测（2026-09-27），只统计 App 进程，不等于真机数值；真机测量尚未完成。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->
