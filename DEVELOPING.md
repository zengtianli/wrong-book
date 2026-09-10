# 错题本 · wrong-book

iPhone、iPad 与 Mac 共用的个人错题工具。公开包不带课程、试卷或用户记录；
新账号为空白，登录后导入自己的图片、同步个人练习，下载完成的资料可离线使用。

## 它做什么

| 入口 | 干什么 |
|---|---|
| **错题本** | 本人已同步的题目，可按学科、题干与待巩固状态查找并打开练习 |
| **导入** | 选择学科与卷子信息，手机/平板拍照或从相册选图，Mac 选择图片文件；确认 AI 说明后逐页上传并查看结果 |
| **复习** | 本人待巩固的题目；练习和进度由共用网页引擎处理 |
| **右上角账号与设置** | 账号、免费 AI 体验资格、同步、离线资料、每日提醒和注销进度 |

## 业务边界

判题、题目生成、复习状态和积分继续使用学习库的网页引擎，原生不复制另一套规则。
题目是否支持变式取决于本人资料中的生成器；导入的固定题目可以原题再练，不能把所有复习都描述为“必出同类新题”。

`PaperScan.Camera` 使用普通系统相机，不提供文档自动找边、透视校正或扫描排序。
图片由 `Api.paperPage` 逐页发往 <https://edu.tianli.cyou>，与网页导入使用同一条服务端识别链。
AI 识别需要免费邀请资格、有效额度和用户确认；费用由开发者承担，识别失败或跳过应如实显示。

`LessonSync` 按账号隔离下载内容与网页存储。导入批次通过 `PaperRequestSession` 绑定开始时的账号和登录 cookie；换账号后停止剩余上传、轮询与绑定同步。已经提交的图片仍属于原账号，不把停止本地任务说成撤回服务器数据。

`Session` 用会话代际保护异步状态回填，并串行执行登录、注册、退出及注销。游客模式不因前台探活自动登录；已有离线账号可重新探活。
账号注销区分即时完成与协调处理的 `pending` 回执，申请受理不等于资料已删除。

## 构建与安装

`project.yml` 是工程源，Xcode 工程由 XcodeGen 生成。iOS 最低版本为 18，macOS 为 15。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme WrongBook -destination 'generic/platform=iOS Simulator' build
```

`sync-lessons.sh` 在构建前生成并校验零课程清单，不依赖作者的私人课程库。
`ci_scripts/ci_post_clone.sh` 在 Xcode Cloud 中复用同一入口，再生成工程。

作者本机可使用仓内 shim 调用共享构建/安装工具：

```bash
bash build-platforms.sh --release
bash install-to-iphone.sh
```

这些 shim 依赖 `~/Dev` 中的共享工具，缺失时会明确退出；它们不属于公开仓的独立构建依赖。
`Shared/PlatformCompat.swift` 是共享源的核验副本，修复应从共享源同步。

## 本地回归

以下回归编译生产实现。会话测试通过本地 URLProtocol 截获 HTTP，不使用真实账号或连接后端。

```bash
xcrun --sdk macosx swiftc Sources/ImportSubjectOptions.swift Tests/ImportSubjectRegression.swift -o /tmp/wrongbook-subject-test
/tmp/wrongbook-subject-test

xcrun --sdk macosx swiftc Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift Tests/PaperSessionRegression.swift -o /tmp/wrongbook-paper-test
/tmp/wrongbook-paper-test

xcrun --sdk macosx swiftc Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift Sources/Session.swift Tests/SessionIdentityRegression.swift -o /tmp/wrongbook-identity-test
/tmp/wrongbook-identity-test
```

个人课程同步及网页存储隔离的回归入口是 `scripts/tests/personal-library.swift`，编译参数见文件头。
`-papertest` 是独立的真实上传自检入口，使用生产登录、压图和上传函数，会创建并清理测试页面；只在指定的隔离测试账号及后端运行。

编译和隔离回归只验证代码路径。正式发布仍需核对 Cloud 源提交、构建 ID、商店资格，以及最终包上的拍照、登录、导入、练习、同步、离线、提醒和注销；审核资料与账号凭证不进入公开仓。
