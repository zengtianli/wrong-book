import SwiftUI
import UserNotifications

/// 我的 —— 登录态、今日进度、每日提醒、课程包版本。
///
/// 这一屏刻意很短。账本、兑换、走势、家长记账全在**另一个 app**（京宝积分）——
/// 2026-08-28 用户拍板「分开2个app，一个关注错题，一个关注积分」。
/// 在这儿再放一个余额大字，就是把那件事又做了半遍。
struct MeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var sync: LessonSync

    private let pack = LessonPack.load()
    @State private var profile: GrowthProfile?
    @State private var remindOn = Reminder.enabled
    @State private var remindHour = Reminder.hour
    @State private var notifyState = "—"
    @State private var planRows: [String] = []
    @State private var askDelete = false
    @State private var deletePw = ""
    @State private var deleteErr: String?

    var body: some View {
        NavigationStack {
            List {
                Section("今天") {
                    if let p = profile {
                        row("已经做了", "\(p.doneToday) / \(p.goal) 题")
                        row("还差", p.remaining == 0 ? "做完了 ✅" : "\(p.remaining) 题")
                        row("等级 / 连续", "Lv.\(p.level) · 🔥 \(p.streakDays) 天")
                    } else {
                        Text("还没做过题 —— 去「学习」挑一课")
                            .font(.footnote).foregroundStyle(Ink.dim)
                    }
                    if let s = session.status {
                        row("今天刷题还能挣", "\(s.practiceLeft) 分")
                    }
                }

                Section {
                    Toggle("每天提醒我做完任务", isOn: $remindOn)
                    if remindOn {
                        Picker("提醒时间", selection: $remindHour) {
                            // 选项里必须包含当前值,否则 Picker 显示成空白 ——
                            // 一个「有开关、没有值」的设置项看着就像坏了(验证时用
                            // -remind_hour 23 当场撞到)
                            ForEach(hourOptions, id: \.self) { Text("\($0):00").tag($0) }
                        }
                    }
                    HStack {
                        Text("通知权限").foregroundStyle(Ink.dim)
                        Spacer()
                        Text(notifyState).foregroundStyle(Ink.dim)
                    }
                    // 把「接下来会说什么」摊开：提醒最怕的是它悄悄不响、
                    // 或者在孩子已经做完时还说「你还差 12 题」。摊开就都看得见。
                    if remindOn {
                        ForEach(planRows, id: \.self) { r in
                            Text(r).font(.caption).foregroundStyle(Ink.dim)
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    // 说清它只在「今天没做够」时才响 —— 否则用户会以为坏了
                    Text("只在当天还没做够 \(pack.dailyGoal) 题时才响；做完了当天就不再提醒。")
                }

                Section("课程包") {
                    row("课数", "\(pack.lessons.count) 课")
                    row("每日任务", "\(pack.dailyGoal) 题")
                    row("更新", sync.running ? "正在拉…" : (sync.note ?? "已是最新"))
                    Button("现在检查更新") { Task { await sync.sync(force: true) } }
                    Button("回到随包发的那一版", role: .destructive) { sync.reset() }
                }

                Section {
                    NavigationLink {
                        PaperScanView().environmentObject(sync)
                    } label: {
                        Label("录卷子", systemImage: "doc.viewfinder")
                    }
                } header: {
                    Text("整卷入档")
                } footer: {
                    // 说清它到哪儿为止 —— 不然会以为拍完就自动进题库了
                    Text("扫一份卷子传到学习库；识别与复盘在 Mac 上做（`paper_ingest pull` → `/exam`）。"
                         + "单道错题不用走这儿，用网页版 wrong.html 更快。")
                }

                Section("账号") {
                    if let s = session.status {
                        row("登录为", s.nick.isEmpty ? s.user : "\(s.nick)（\(s.user)）")
                        Button("退出登录", role: .destructive) { Task { await session.logout() } }
                        Button("注销账号", role: .destructive) { deletePw = ""; askDelete = true }
                    } else {
                        // 没登录也能做题，但要说清代价 —— 不然「分怎么不涨」查不出来
                        Text("没有登录：题照做，但**刷题积分不记账、进度不跨设备**。")
                            .font(.footnote).foregroundStyle(Ink.dim)
                        Button("去登录") { Task { await session.logout() } }
                    }
                }

                Section {
                    Text("题、题库、学习路径的 SSOT 都在 edu.tianli.cyou；"
                         + "这个 app 只是把它们装在身上，离线也能做。")
                        .font(.caption).foregroundStyle(Ink.dim)
                }
            }
            .navigationTitle("我的")
        }
        .task { await load() }
        // App Store 5.1.1(v)：能注册就必须能在 app 内删号。要密码，二次确认，文案说清删什么。
        .alert("注销账号？", isPresented: $askDelete) {
            SecureField("当前密码", text: $deletePw)
            Button("永久删除", role: .destructive) {
                Task {
                    if await session.deleteAccount(password: deletePw) { deleteErr = nil }
                    else { deleteErr = session.error }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账号、刷题积分、学习进度、拍过的错题与卷子会一起删除，不可恢复。输入当前密码确认。")
        }
        .alert("没删成", isPresented: Binding(get: { deleteErr != nil }, set: { if !$0 { deleteErr = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(deleteErr ?? "") }
        .onChange(of: remindOn) { _, v in
            Reminder.enabled = v
            // ask: true 只在这儿 —— 用户自己拨了开关，这时问权限才不算打扰
            Task { notifyState = await Reminder.reschedule(ask: true); await refreshPlan() }
        }
        .onChange(of: remindHour) { _, v in
            Reminder.hour = v
            Task { notifyState = await Reminder.reschedule(); await refreshPlan() }
        }
    }

    private var hourOptions: [Int] {
        Array(Set([16, 17, 18, 19, 20, 21] + [remindHour])).sorted()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Ink.dim); Spacer(); Text(v).foregroundStyle(Ink.text) }
    }

    private func load() async {
        if let snap = try? await EduArchive.shared.snapshot() {
            profile = GrowthProfile.parse(archive: snap)
        }
        notifyState = await Reminder.permissionText()
        await refreshPlan()
    }

    private func refreshPlan() async {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:00"
        planRows = await Reminder.currentPlan().prefix(3).map { "\(f.string(from: $0.fire))　\($0.body)" }
        if planRows.isEmpty && remindOn { planRows = ["今天已经做够了，今天不再提醒"] }
    }
}
