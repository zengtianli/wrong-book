# CLAUDE.md · wrong-book（错题本）

> iOS app。**装着 `~/Edu` 的练习引擎**，离线做题；错题按「题型」复习出同类新题。
> 姊妹 app：`~/Apps/ios/points-deck`（京宝积分，管账本）。
> 2026-08-28 用户拍板「分开2个app，一个关注错题，一个关注积分」—— 别再合并回去。

## 这个 app 的一句话

它是 <https://edu.tianli.cyou> 的**离线随身版**，不是一个新产品。
题、题库、学习路径、判题、勋章、上瘾机制全在 `~/Edu`；这边只提供三样东西：
**离线**、**原生错题本入口**、**每日任务提醒**。

## 硬约束（违反其一，这个 app 就没有存在理由了）

| 约束 | 为什么 |
|---|---|
| **不用 SwiftUI 重写练习引擎** | `~/Edu/engine/practice.js` 1200+ 行装着判题 `verify()`、组卷权重 `nextGen()`、错题本两层、勋章判定 `PRED`；题库**内联进每个 HTML**。重写 = 第二份判题逻辑，和 `bank.db` / `badges.json` 必然漂移 |
| **不做后端、不复刻算分** | 刷题积分由页面里的 `points_client.js` 走 `/api/practice`，**每日上限在服务端**。原生这边连一个加号都不许有 |
| **错题本只读** | 收进 / 划掉都是引擎干的。原生也能改 = 两边迟早说不同的话，而且不报错 |
| **错题条目里没有 `ans` / `options`** | 用户原话「为了防止记住答案，错的题目也要变下」。数据结构里就没有，所以想重放原题也放不出来 |
| **页面不进本仓** | SSOT 在 `~/Edu`。`sync-lessons.sh` 构建前组装，和上线共用同一道 PII 门 |
| **`archive/` 的任何东西不进包** | 孩子姓名、成绩、作文、试卷原图。`app_pack.py` 里那道 PII 门是 fail-closed 的 |
| **不用 `.page` 分页 TabView** | 练习页自己带左右滑翻题（`bindNav()`），外壳再套横向分页手势会抢 |
| **亮色** | 练习页是亮色自包含单文件，深壳套亮页每次进课都闪一下白 |
| **「录卷子」只传图，不识别** | 读图那步（哪道题/标答/孩子答了什么/失分归哪根轴）是人和 LLM 一起判的活。塞进 app 等于把「读不准就别猜」交给没人看的日志。手机到「传上去」为止，`/exam` 在 Mac 上做 |
| **单道错题不走 app** | 网页 `wrong.html` + `wrong_ingest.py` 2026-08-16 就有了，手机 Safari 打开就能传。app 这一屏只解决**整卷**（多页 + 页序 + 文档扫描） |

## 跑起来

```bash
bash sim-run.sh                 # 编译 + 装模拟器 + 截一张图（总部 SSOT 的 shim）
bash install-to-iphone.sh       # 装真机（默认走 WiFi）
bash sync-lessons.sh            # 单独同步一次课页（构建时会自动跑）
python3 make_icon.py            # 重生图标（逐像素可复现）
```

### 「录卷子」这一屏

原生独占的那一条能力是 `VNDocumentCameraViewController`：卷子是**文档**不是风景，
手机浏览器只能调普通相机，拍出来斜、有阴影、边不齐，而读图那步要认密密麻麻的题干和红笔批改
—— 畸变直接变成「读出一道错的题」。系统扫描器白送自动找边 + 去透视 + 多页 + 重拍 + 排序。

```
手机（我的 → 录卷子）→ POST edu.tianli.cyou/api/paper_page
   → Mac: python3 ~/Edu/engine/paper_ingest.py pull <slug>   # 落 archive/<slug>/scans/，VPS 侧删
   → Mac: CC 会话 /exam                                       # 读图 → paper.yaml / review.md
```

### 验证通道（launch 参数，生产路径上永远是 nil）

```bash
UDID=$(xcrun simctl list devices booted --json | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print([x["udid"] for v in d.values() for x in v if x["state"]=="Booted"][0])')
xcrun simctl launch $UDID cyou.tianli.wrongbook \
  -api_base 'http://127.0.0.1:8799' \      # 指向本地临时账本，别打生产
  -dev_user testkid -dev_pw 'Test@2026' \  # 跳过手输登录
  -tab 1 \                                 # 落到错题本
  -review 'remainder-basics:only-r'        # 直接进某一类的复习
  # 或 -lesson remainder-basics            # 直接开一课（验「不登录不联网也能做」）
  # 或 -paperscan 1                        # 直接开「录卷子」（它藏在「我的」二级页）
  # 或 -papertest 1 -papertest_user jingbao -papertest_pw 160912
  #                                        # 跑一遍**真实上传路径**并把结果画在屏上
```

`-papertest` 存在的理由：这一屏最容易错的不是布局，是「压出来的图服务端收不收」——
dataURL 前缀、字段名、大小上限，任何一处对不上都只表现为一句笼统的 400。
而这条路人得用手点相册才走得到。它跑的是 `PaperScan.jpeg` + `Api.paperPage` **本身**，
不是照着重写一遍（重写的那种「实测」测的是替身，会假绿）。
2026-08-31 实测：压图 931KB（1760×2400，走到阶梯第一档）→ 上传成功 →
坏 slug `../etc` 被服务端拒 → 服务端侧独立核验落盘是完整 JPEG（ffd8…ffd9）。

`-review` 存在的理由：**「复习出的是同类新题、不是原题」这条只能靠手点验**，
而手点验不了的东西等于没验过。2026-08-28 实测：错题记的是 `255 ÷ 12`，
复习出来的是 `133 ÷ 8`，同题型不同题，页面上标着「🔁 这类你错过 3 次 · 换了道新题」。

### 起一个本地临时账本（别拿生产账本做实验）

```bash
D=/private/tmp/edu-pts-ios2
lsof -ti :8799 | xargs -r kill -9
mkdir -p $D/home $D/site && cp ~/Edu/points/{login,points,me,wrong}.html $D/site/
python3 ~/Edu/engine/app_pack.py $D/site/app            # 增量更新的下载源
cd ~/Edu/points && EDU_POINTS_HOME=$D/home EDU_POINTS_STATIC=$D/site EDU_POINTS_PORT=8799 \
  EDU_KID_PW=Test@2026 EDU_PARENT_PW=Parent@2026 python3 server.py init
cd ~/Edu/points && EDU_POINTS_HOME=$D/home EDU_POINTS_STATIC=$D/site EDU_POINTS_PORT=8799 \
  nohup python3 server.py serve > $D/server.log 2>&1 &
```

⚠ 服务只 bind IPv4 `127.0.0.1`（`server.py` 写死）—— baseURL 写 `http://127.0.0.1:8799`，
别写 `localhost`（会先试 `::1` 被拒再回落）。**真机连不上本地服务**，只能用模拟器。
ATS 不拦回环地址（2026-08-28 模拟器实测通过，不用改 Info.plist）。

## 结构

| 文件 | 干什么 |
|---|---|
| `Sources/Api.swift` | 只管登录态。`base` 可被 `-api_base` 覆盖 |
| `Sources/Session.swift` | 登录 / 探活 / 「先不登录直接做题」 |
| `Sources/Lessons.swift` | manifest 的投影 + 三层分组 + **下载副本优先**的文件解析 |
| `Sources/LessonSync.swift` | 增量更新：拉 `/app/manifest.json` → 比 sha256 → 下 → **验 sha256** → 全对才换清单 |
| `Sources/LessonWebView.swift` | 承载引擎。`loadSimulatedRequest` 挂真 origin + cookie 交接 + 切后台落档 |
| `Sources/EduArchive.swift` | 原生**只读**引擎写的 localStorage（离屏 WebView，同 origin 同分区） |
| `Sources/WrongBook.swift` | 错题两层模型 + 成长档案投影 |
| `Sources/Reminder.swift` | 每日任务提醒（重排未来 7 天，今天做够了就不排今天） |
| `Sources/{Learn,WrongBook,Me,Login,Home}View.swift` | 界面 |

## 它依赖 `~/Edu` 的两个 JS 入口（少了就静默失灵）

```
window.__PRACTICE__.review(gid)    错题本点「复习」→ 引擎出同类新题
window.__EDU_POINTS__.flush(true)  切后台前把学习存档落一次（sendBeacon）
```

两个都在 `~/Edu` 那边（`engine/practice.js` / `points/points_client.js`），
**内联进每个 HTML**。改了引擎必须全量重渲，否则包里还是旧版。
`sync-lessons.sh` 里有一道门专门查这个（只查 `kind: practice` 的页；
精讲页 `kind: teach` 不带引擎，本来就没有这两个入口）。

## 已知的、不是 bug 的行为

- **第一次同步存档后，当前这一页不刷新**：`points_client.js` 只在「本地本来就有档」时才
  `location.reload()`。所以刚登录进的第一课会显示 Lv.1 / 0 题，退出来再进就对了。
  这是 ~/Edu 的既有行为，不在这个 app 里绕过去（绕 = 第二份同步逻辑）。
- **课页的 sha256 和站上 `/primary-*/` 那份对不上**：站上那份在剥离之后又注了反馈浮标，
  字节必然不同。所以增量更新的下载源是 `/app/`（`app_pack` 的原样产物）。

## 相关

- 方案全文：`~/Dev/wiki/handoffs/dev/ios-fleet-landing/06-练习平台app方案.md`
- 舰队规则：`/appios`（起新 app、装机、图标、Xcode 挑选）
- 内容 SSOT：`~/Edu`（`/course` 加课、`/check` 跑门、`/ship` 上线）
