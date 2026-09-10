import SwiftUI
import UserNotifications

/// 我的 —— 登录态、今日进度、每日提醒、课程包版本。
///
/// 首屏只放常用入口，提醒、课程和账号管理各自在独立页面。
/// 账本、兑换、走势、家长记账全在**另一个 app**（京宝积分）——
/// 2026-08-28 用户拍板「分开2个app，一个关注错题，一个关注积分」。
/// 在这儿再放一个余额大字，就是把那件事又做了半遍。
struct MeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var sync: LessonSync

    private var pack: LessonPack { LessonPack.load() }
    @State private var profile: GrowthProfile?
    @State private var remindOn = Reminder.enabled
    @State private var remindHour = Reminder.hour
    @State private var notifyState = "—"
    @State private var planRows: [String] = []
    @State private var askDelete = false
    @State private var deletePw = ""
    @State private var deleteErr: String?
    @State private var path: [Destination] = []

    private enum Destination: Hashable {
        case account, scan, reminders, downloads
    }

    private var accountName: String {
        guard let s = session.status else { return "登录或注册，开始导入错题" }
        return s.nick.isEmpty ? s.user : "\(s.nick)（\(s.user)）"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    entry("账号与隐私", detail: accountName, icon: "person.crop.circle",
                          destination: .account, key: "a")
                    entry("每日提醒", detail: remindOn ? "每天 \(remindHour):00" : "未开启",
                          icon: "bell", destination: .reminders, key: "r")
                    entry("离线课程", detail: "\(pack.lessons.count) 课 · \(sync.note ?? "已下载内容可离线练习")",
                          icon: "arrow.down.circle", destination: .downloads, key: "d")
                }
                Section("今天") {
                    if let p = profile {
                        row("已经做了", "\(p.doneToday) / \(p.goal) 题")
                        row("还差", p.remaining == 0 ? "做完了 ✅" : "\(p.remaining) 题")
                    } else {
                        Text("从自己的错题照片开始，导入后再练习")
                            .font(.footnote).foregroundStyle(Ink.dim)
                    }
                }

            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .account: accountPage
                case .scan: PaperScanView().environmentObject(sync)
                case .reminders: remindersPage
                case .downloads: downloadsPage
                }
            }
        }
        .task { await load() }
        .onChange(of: sync.revision) { _, _ in Task { await load() } }
        .onChange(of: remindOn) { _, v in
            Reminder.enabled = v
            Task { notifyState = await Reminder.reschedule(ask: true); await refreshPlan() }
        }
        .onChange(of: remindHour) { _, v in
            Reminder.hour = v
            Task { notifyState = await Reminder.reschedule(); await refreshPlan() }
        }
    }

    private func entry(_ title: String, detail: String, icon: String,
                       destination: Destination, key: KeyEquivalent) -> some View {
        Button { path.append(destination) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(Ink.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(Ink.text)
                    Text(detail).font(.caption).foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .keyboardShortcut(key, modifiers: [.command, .shift])
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("me.\(destination)")
    }

    private var remindersPage: some View {
        List {
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

        }
        .navigationTitle("每日提醒")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var downloadsPage: some View {
        List {
            Section("课程包") {
                    row("课数", "\(pack.lessons.count) 课")
                    row("每日任务", "\(pack.dailyGoal) 题")
                    row("更新", sync.running ? "正在拉…" : (sync.note ?? "已是最新"))
                    Button("现在检查更新") { Task { await sync.sync(force: true) } }
                    Button("停用本机课程副本", role: .destructive) { sync.reset() }
                }

            Section {
                Text("App 不预装个人资料。登录后可导入自己的错题照片；已同步的个人课程支持离线练习。")
                    .font(.caption).foregroundStyle(Ink.dim)
            }
        }
        .navigationTitle("离线课程")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountPage: some View {
        List {
            Section("账号") {
                    if LessonPaths.offlineReadOnly {
                        Text("离线模式：仅使用本机资料，未验证当前登录状态。")
                            .font(.footnote).foregroundStyle(Ink.dim)
                    }
                    if let s = session.status {
                        row("登录为", s.nick.isEmpty ? s.user : "\(s.nick)（\(s.user)）")
                        Button("退出登录", role: .destructive) { Task { await session.logout() } }
                            .disabled(session.busy)
                        Button("注销账号", role: .destructive) { deletePw = ""; askDelete = true }
                            .disabled(session.busy)
                        if let receipt = session.deletionReceipt, receipt.owner == s.user, receipt.status == "pending" {
                            Text("注销处理中 · 尚未完成删除").foregroundStyle(Ink.dim)
                            Text("预计处理日期：\(receipt.expectedBy.prefix(10))").font(.footnote)
                            Button("刷新注销进度") { Task { await session.refreshDeletion() } }
                            if let error = session.deletionRefreshError { Text(error).font(.footnote).foregroundStyle(Ink.red) }
                            Link("联系支持", destination: URL(string: "https://app-ios-wrong-book.tianli.cyou/support.html")!)
                        }
                    } else {
                        // 没登录也能做题，但要说清代价 —— 不然「分怎么不涨」查不出来
                        Text("登录或邮箱注册后，导入自己的错题照片并同步学习资料。")
                            .font(.footnote).foregroundStyle(Ink.dim)
                        Button("去登录") { Task { await session.logout() } }
                    }
                }

        }
        .navigationTitle("账号与隐私")
        .navigationBarTitleDisplayMode(.inline)
        // App Store 5.1.1(v)：能注册就必须能在 app 内删号。要密码，二次确认，文案说清删什么。
        .alert("注销账号？", isPresented: $askDelete) {
            SecureField("当前密码", text: $deletePw)
            Button("确认注销", role: .destructive) {
                Task {
                    if await session.deleteAccount(password: deletePw) { deleteErr = nil }
                    else { deleteErr = session.error }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(AccountDeletionCopy.summary + "删除完成后不可恢复。输入当前密码确认发起注销。")
        }
        .alert("没删成", isPresented: Binding(get: { deleteErr != nil }, set: { if !$0 { deleteErr = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(deleteErr ?? "") }
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
