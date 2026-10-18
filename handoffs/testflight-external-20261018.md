# 错题本 iOS TestFlight 外部测试 · 2026-10-18

本轮状态：**外部测试配置与 Beta 提交已完成，Apple Beta 审核 WAITING_FOR_REVIEW**。只处理 TestFlight 外部测试；不提交、重提或回复正式 App Store 审核，不构建、不重传、不装机。完成后只本地提交，推送交 Chapter。

## 身份、范围与原流程

- Chapter task：`e507ae9ac2bf4533aa47ed5d5f063a6e`；复用 claims PID `15817` / session `chapter-task:e507ae9ac2bf4533aa47ed5d5f063a6e`，写前 check 已通过，不另开或释放声明。
- 唯一写入文件：本文件。保留其他会话源码、暂存、验收资料和后台。
- 执行机：`TianliMac-Mini.local`；源码起点：`bb01eab`，分支 `main`。此源码起点不作为云端 build24 的源码证明。
- 共享资源：ASC App `6806626967` / `cyou.tianli.wrongbook`，平台限定 `IOS`；既有内部 `family` 组不改。
- 方法：[Mac 批次 SOP 第 3–7 步](/Users/tianli/Apps/keyscope/handoffs/2026-10-18-app-review/testflight-mac-batch.md)、[Apple 审核流程](/Users/tianli/Dev/tools/cc-home/skills/app/references/app-store-review.md)。官方 SDK：`/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/asc.py`；解释器 `/Users/tianli/Dev/.venv/bin/python`；凭证沿原入口，不入库。
- 完成条件：最新 VALID 未过期 IOS build；独立外部组及三位指定邮箱；Beta 审核联系人与正式审核一致；主要流程 What to Test；自动通知；仅在缺失时创建 Beta submission；逐项 GET 回读及正式对象前后比较；只提交本文件。

## 14:40–14:42 上海：只读基线

- App 当前显示名称：`错题本随身版`，primaryLocale `zh-Hans`。
- 完整分页查询 IOS builds 共 **30** 个；按 `-uploadedDate` 最新为 **1.0.1 (24)**，build ID `5d458514-eb29-4caa-bb4e-d3b1bdec6425`，preReleaseVersion ID `bcf679ec-9424-4262-a8f5-cdd8decc1745` / `IOS`。
- build24：`processingState=VALID`、`expired=false`、`buildAudienceType=APP_STORE_ELIGIBLE`、`usesNonExemptEncryption=false`；上传 `2026-10-17T07:09:14-07:00`，到期 `2027-01-15T06:09:14-08:00`。
- buildBetaDetails ID 与 build 相同：`autoNotifyEnabled=true`、`internalBuildState=IN_BETA_TESTING`、`externalBuildState=READY_FOR_BETA_SUBMISSION`。
- `/betaAppReviewSubmissions?filter[build]=5d458514-eb29-4caa-bb4e-d3b1bdec6425` 完整结果 `[]`。Beta build 本地化只有 `zh-Hans`，ID `66b67891-7f80-4004-939d-bf1da5bedb20`，`whatsNew=null`；App 级 Beta 本地化 `[]`。
- 现有 betaGroups 只有内部 `family`，ID `62b2ac52-bbeb-47e8-84cb-1f8b528e1234`，`isInternalGroup=true`。
- 正式审核资料来源：最新 IOS 1.0.1 版本 `c2314f83-7cf1-47df-b2d1-70a7a794e9e4` / review detail `fce89965-8852-4e81-a947-2d7b82bd8af2`；四个联系人字段齐全，`demoAccountRequired=true`，演示账号/密码齐全，Notes 3072 字。敏感字段只在内存中复制并比较，不写本文件。

正式对象基线（GET，非写入）：

| 对象 | ID | 状态 / build |
| --- | --- | --- |
| IOS 1.0.1 | `c2314f83-7cf1-47df-b2d1-70a7a794e9e4` | `PREPARE_FOR_SUBMISSION` / build23 `e84ad64c-d54f-448c-8386-1a3d5d697da0` |
| IOS 1.0 | `e0e79625-a486-4881-9c7e-ea5313839e94` | `READY_FOR_SALE / READY_FOR_DISTRIBUTION` / build18 `567bec28-e5a2-413a-bd02-7b2e04bf2586` |
| 正式 submission | `eba46f4f-ae5a-4a91-9283-11bc69d22a7e` | `COMPLETE` |
| 正式 submission | `5271c7b0-6329-49f5-a7ca-04cf8ff586cc` | `COMPLETE` |

全部正式 versions、reviewSubmissions 与每个 version 的 build relationship 以 `json.dumps(sort_keys=True,separators=(',',':'))` 规范化，基线 SHA-256：`baf3a99806b6d3cea1695739c7c5979ca6ced82a45c3632620c942051ee294a5`。

只读参数纠正：查询 `appStoreVersionLocalizations` 时错误包含不属于该资源的 `privacyPolicyUrl`，Apple 返回 HTTP400 `PARAMETER_ERROR.INVALID`（request error ID `11eca410-c839-44f9-a3f0-43165c0d677b`）；未产生写入，已以正确资源补查隐私链接。

## 第 3 步：独立外部组与测试者

- 14:41:59 上海，`POST /betaGroups` 创建 `External iOS · 2026-10-18`，返回 ID `76f69d8b-2ebc-4173-855c-04fc2cb65bb0`；随后 GET 精确回读 `isInternalGroup=false`、`publicLinkEnabled=false`、`feedbackEnabled=true`。现有内部组保持原样。
- 逐邮箱查询均带 `filter[apps]=6806626967`：账号1已有 tester `890e42d4-afbd-46a8-9494-8525a1901040` / `INSTALLED`，账号2已有 tester `d755b2ec-539b-4fd1-a5fe-9de217bd8412` / `INVITED`，账号3在本 App 返回 `[]`。
- 账号1基线已有 `appDevices` 记录 `IOS / 1.0.1 (24)`；这是既有安装记录，本轮未安装或验证客户端业务，也不是外部测试邀请成功的证据。
- 商店介绍、支持/营销链接已从最新正式版本读取；隐私链接改从 `appInfoLocalizations` 正确资源读取，为 `https://app-ios-wrong-book.tianli.cyou/privacy.html`。上述 GET 全部成功。
- 对账号1、2分别 `POST /betaGroups/76f69d8b-2ebc-4173-855c-04fc2cb65bb0/relationships/betaTesters`，均 HTTP204；每次随即 GET 组成员确认。对账号3 `POST /betaTesters` 并同时关联本组，返回 tester `22aca005-d5be-47ff-88cb-bf1d75f90c5d`，随后 GET 已在组中、状态 `NOT_INVITED`。

| 邮箱 | 本 App tester ID | 加组后状态（App 级） |
| --- | --- | --- |
| zengtianli1@126.com | `890e42d4-afbd-46a8-9494-8525a1901040` | `INSTALLED`（既有记录） |
| zengtianli2@126.com | `d755b2ec-539b-4fd1-a5fe-9de217bd8412` | `INVITED`（既有记录） |
| zengtianli3@126.com | `22aca005-d5be-47ff-88cb-bf1d75f90c5d` | `NOT_INVITED` |

未新建 ASC 团队用户或扩大角色权限。App 级旧 `INVITED / INSTALLED` 不证明本轮外部邀请已发；账号3仍待可安装包与通知。

## 第 4 步：Beta 审核资料与 What to Test

- `PATCH /betaAppReviewDetails/6806626967` 返回 HTTP200；随后 GET 精确比对四个联系人字段、演示账号/密码、`demoAccountRequired=true` 与 Notes，全部等于上述正式 1.0.1 审核资料；Notes 3072 字。没有打印或入库账号密码、私人联系方式。
- `POST /betaAppLocalizations` 新建 `zh-Hans`，返回 ID `8665d5c4-9416-47ef-b35d-0342a53a42bc`；GET 确认 description 与正式介绍逐字相同（739 字），feedbackEmail 等于原审核联系人，marketingUrl 与原正式资料一致，privacyPolicyUrl 与原隐私链接一致。
- `PATCH /betaBuildLocalizations/66b67891-7f80-4004-939d-bf1da5bedb20` 返回 HTTP200，随后 GET 确认 `locale=zh-Hans`，`whatsNew` 与下文逐字一致。

What to Test：

> 请测试错题本随身版的主要流程：注册、登录与找回账号；拍照或相册选图、选择学科、确认或拒绝 AI 上传同意、查看识别结果并对照原图；将错题加入个人资料、练习答题与判题、复习及重启后保存；跨设备同步、离线资料和提醒；免费识别额度、Apple 订阅购买与恢复。账号注销与进度查询请使用独立可删除的测试账号。请反馈无法完成的操作、识别或判题异常、看不懂的说明和不顺手之处，并注明设备、系统和复现步骤。

## 第 5–6 步：关联构建、自动通知与 Beta 提交

- `POST /betaGroups/76f69d8b-2ebc-4173-855c-04fc2cb65bb0/relationships/builds` 返回 HTTP204，随后 GET 组 builds 仅包含 build24 `5d458514-eb29-4caa-bb4e-d3b1bdec6425`。
- `autoNotifyEnabled=true` 原已开启，保留并再次 GET 确认，不重复无效 PATCH。
- 创建前再次完整 GET 指定 build 的 Beta submissions，仍为 `[]`；才执行唯一一次 `POST /betaAppReviewSubmissions`，返回 ID `5d458514-eb29-4caa-bb4e-d3b1bdec6425` / `WAITING_FOR_REVIEW`。
- 随即 GET 确认仅一个 submission，状态 `WAITING_FOR_REVIEW`，submittedDate `2026-10-17T23:43:37-07:00`（上海 **2026-10-18 14:43:37**）。这是 **TestFlight Beta 审核**，不是正式 App Store 审核；尚未批准外部安装。
- 等待期间不重复提交或反复发送邀请；批准后沿原队列回读测试者状态，只补仍缺失的通知。本轮未调用 `betaTesterInvitations`，未遇到 `NO_INSTALLABLE_BUILDS`。

## 第 7 步：14:44:23 上海最终官方 GET 回读

- 完整分页复核仍共30个 IOS builds，最新 VALID、未过期包仍为 **1.0.1 (24)**；未上传任何新包。
- 外部组 `76f69d8b-2ebc-4173-855c-04fc2cb65bb0`：`isInternalGroup=false`、公开链接关闭，唯一 build 为24，三邮箱与上表 tester ID 均在组中，状态仍分别 `INSTALLED / INVITED / NOT_INVITED`。
- Beta submission `5d458514-eb29-4caa-bb4e-d3b1bdec6425`：`WAITING_FOR_REVIEW`；其 `/build` 关系精确回读为24。`buildBetaDetails`：`externalBuildState=WAITING_FOR_BETA_REVIEW`、`internalBuildState=IN_BETA_TESTING`、`autoNotifyEnabled=true`。
- Beta 联系人、演示账号、Notes 再次与正式源逐字段相等；Beta description、反馈邮箱、隐私链接和 What to Test 再次回读通过。
- 内部 `family` 保持原 ID / `isInternalGroup=true` / `hasAccessToAllBuilds=true`；本轮未向该组写入。
- 正式 versions、正式 reviewSubmissions 与两个正式 version 的 build relationship 的规范化 SHA-256 仍为 `baf3a99806b6d3cea1695739c7c5979ca6ced82a45c3632620c942051ee294a5`，**与基线完全一致**。正式1.0.1仍为草稿、关联23；正式1.0仍在售、关联18；两份正式 submission 仍 COMPLETE。
- 本轮没有正式审核写入、回复、重提或商店版本关联变更。API/文档配置任务无需构建、模拟器或源码测试；没有把 API 通过记作真机业务通过。

## 本地提交与 Chapter 接续

- 远端 `zengtianli/wrong-book` 经 `gh repo view --json nameWithOwner,isPrivate` 回读为 **公开仓库**（`isPrivate=false`）。本轮只在本地提交本文件；不自行推送，Chapter 按公开仓规则合成本人决定卡。未推送不属于本轮 blocked。
- `handoffs/` 被 `.gitignore:41` 排除；按本人点名提交本文件的授权，仅对这个路径强制加入，不更改忽略规则。敏感审核凭证及私人联系字段未入文件。
- 本轮没有调用推送器或运行 git push，未触发 Xcode Cloud；推送前的 `chapter xcode-cloud status --repo . --json` 和 pre-push 闸由 Chapter 在实际推送阶段执行，不把未运行推送阶段写成失败或前置条件未满足。
- Apple 等待为正常 Beta 排队；外部批准、账号3通知/接受、收件箱投递和本轮新安装尚未证明。批准后仍沿原 Beta submission / 外部组接续，不重建、不重传、不重复提交。
- 提交前本地校验通过：What to Test 与 ASC 逐字一致；三邮箱齐全；本文件没有正式演示账号、密码或联系手机号。所有步骤均完成预定回读；提交范围仅本文件，提交号通过 `git log -1 -- handoffs/testflight-external-20261018.md` 查询。
- 提交守卫提示路径处于 Chapter 原范围声明内；已按本人指定的 PID/session 再次 check，通过。交接 Chapter：本文件为本轮新建，逐行差异均属本轮，其他暂存和修改不纳入提交；保留原声明，由 Chapter 收尾释放。
- Apple 对外测与通知的说明：[邀请外部测试者](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)。本文件中的实际状态以本轮官方 API 回读为准。
