<p align="center"><img src="Resources/icon-1024.png" width="96" alt="错题本"></p>

# 错题本 · wrong-book

**导入自己的错题照片，整理、练习、复习。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

扫描或从相册导入自己的错题照片，识别后整理为个人练习资料。学习内容按账号隔离，公开安装包不附带任何用户的个人资料。



## 它做什么

| 功能 | 说明 |
|---|---|
| **自己的错题随身复习** | 查看错题记录并打开对应练习。可用题目由自己的导入内容决定，不承诺每道题都有变式。 |
| **自己的错题，自己的学习资料** | 新安装为空白错题本。登录后导入错题照片，识别结果与课程按账号隔离；已同步的个人课程支持离线练习。 |
| **录卷子用系统文档扫描器** | 卷子是文档不是风景：自动找边、去透视、多页、排序。一页一页传回学习库，服务端自动读出错题逐道入库——和网页传图走同一条链，不做第二条通路。 |

## 怎么拿到

TestFlight 内测中，暂未开放公开链接。

公开安装包不附带题库、个人课程或错题照片。登录后通过个人学习库导入、同步自己的内容。

## 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme WrongBook -destination 'generic/platform=iOS Simulator' build
```

- 仓里的 `*.sh` 是作者本机舰队脚本的 shim（三平台构建 / 真机装机 / TestFlight），依赖 `~/Dev` 下的总部工具，不在本仓；没有那套工具时它们会明确退出。
- `Shared/PlatformCompat.swift` 是总部共享文件的逐字节副本（iOS-only SwiftUI 修饰符在 macOS 侧的同名 no-op），别在这里改它。
- `project.yml` 的 preBuildScripts 会跑 `sync-lessons.sh`，生成并校验空白学习清单，构建不访问作者的私人内容库。

开发细节（回归、验证通道、约束）见 [DEVELOPING.md](DEVELOPING.md)。

## 相关

- 产品页：<https://apps.tianli.cyou/p/wrong-book-ios.html>
- 舰队总览（10 个 app 怎么来的）：<https://apps.tianli.cyou/ios.html>
- 教程：[从零到 TestFlight：一个人做 iPhone app 的完整路径](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 曾田力 (Tianli Zeng)
