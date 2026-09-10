<p align="center"><img src="Resources/icon-1024.png" width="96" alt="错题本"></p>

# 错题本 · wrong-book

**整理自己的错题，留给下一次更有把握的作答。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

从自己的试卷与错题照片开始，把零散的学习资料整理起来，方便持续复习。新账号和公开安装包都是空白个人错题本，学习资料与记录按账号隔离。

三个入口是错题本、导入、复习，账号、提醒和离线管理位于右上角设置。iPhone / iPad 使用普通相机拍照或从相册选择图片，Mac 选择图片文件；确认上传后由共用学习库服务识别。练习和复习使用自己的题目，不承诺每道题都有同类变式。


## 它做什么

| 功能 | 说明 |
|---|---|
| **自己的错题，自己整理** | 导入自己的错题照片，建立个人学习资料。新账号从空白开始。 |
| **下载自己的练习，离线复习** | 登录后同步本人资料，下载好的练习可以离线使用；不同账号的学习记录分别保存。 |
| **拍照或选择图片后导入** | 手机和平板可拍照或从相册选图，Mac 可选择图片文件。上传前确认学科、页码及 AI 识别说明，逐页上传并查看识别结果。每账号前 10 张免费，之后可选择 Apple 月订阅或年订阅继续识别，无需邀请码或 API 密钥。 |

## 怎么拿到

TestFlight 内测中，暂未开放公开链接。

公开包不附带个人课程或题库；练习材料由用户自行导入，sync-lessons.sh 只维持零课程公开包。

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
