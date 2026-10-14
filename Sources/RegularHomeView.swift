import SwiftUI

/// 宽屏主页：iPad（全屏 / 宽分屏）、Mac、Vision Pro。
///
/// 三个入口和 iPhone 一样（错题本 / 复习 / 导入），账号与设置仍在右上角。侧栏下面多一块「今天」：
/// 待巩固几类、今天做了几题、连续几天 —— 和 Apple Watch 同一份摘要（ReviewDigest），数字对得上。
/// 错题本与复习是「列表 + 题目」并排：点一道题，右边直接开练习页（同一个 LessonScreen、同一套引擎），
/// 列表不动，做完一组回来接着点下一道。iPhone 与 iPad 窄分屏仍是 HomeView 的标签页，一个像素都不动。
struct RegularHomeView: View {
    @EnvironmentObject var session: Session
    @StateObject private var sync = LessonSync.shared
    // 验证通道：和 iPhone 一样认 `-tab 0/1/2`（错题本 / 导入 / 复习），方便 headless 截图
    @State private var section: HomeSection? = HomeSection(rawValue: UserDefaults.standard.integer(forKey: "tab")) ?? .library
    @State private var selection: ReviewTarget?
    @State private var settings = false
    @State private var digest: ReviewDigest?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { Task { await sync.sync(force: true) } } label: { Label("同步错题", systemImage: "arrow.clockwise") }
                            .disabled(sync.running)
                            #if !os(macOS)
                            .keyboardShortcut("r", modifiers: .command)
                            #endif
                        Button { settings = true } label: { Label("账号与设置", systemImage: "person.crop.circle") }
                            #if !os(macOS)
                            .keyboardShortcut(",", modifiers: .command)
                            #endif
                    }
                }
        }
        .tint(Ink.accent)
        .environmentObject(sync)
        .sheet(isPresented: $settings) {
            SettingsSheet { settings = false }.environmentObject(sync)
                #if !os(iOS)
                .frame(minWidth: 460, minHeight: 620)
                #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .wrongbookImport)) { _ in section = .importing }
        .onChange(of: section) { _, _ in selection = nil }
        .modifier(HomeLifecycle(sync: sync))
        // 侧栏的「今天」：课程同步完、做完一组回来（列表重读）时都重算
        .task(id: sync.revision) { await loadDigest() }
        .onChange(of: selection?.id) { old, new in
            if old != nil, new == nil { Task { await loadDigest() } }
        }
    }

    // ── 侧栏 ────────────────────────────────────────────────────────────────
    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(HomeSection.allCases) { s in
                    Label(s.title, systemImage: s.icon)
                        .badge(s == .review ? (digest?.due ?? 0) : 0)
                        .tag(s)
                }
            }
            Section("今天") {
                TodayCard(digest: digest)
            }
            if let note = sync.note {
                Section {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("错题本")
    }

    // ── 右边 ────────────────────────────────────────────────────────────────
    @ViewBuilder
    private var detail: some View {
        switch section ?? .library {
        case .library, .review:
            LibraryBoard(reviewOnly: section == .review, selection: $selection, digest: digest)
                .navigationTitle((section ?? .library).title)
                .navigationBarTitleDisplayMode(.inline)
        case .importing:
            // 导入是一张表单：收在 720 以内居中，两边留纸面
            PaperScanView()
                .contentWidth(720)
                .paperPanel()
        }
    }

    /// 和错题本列表同一个来源：本机练习引擎的存档；本机还没练过的课用服务端存档补（FocusLibraryView.reload 同一口径），
    /// 今日进度（edu:@profile）本机没有时也用服务端那份。
    private func loadDigest() async {
        let pack = LessonPack.load()
        guard !pack.lessons.isEmpty else { digest = nil; return }
        do {
            var snapshot = try await EduArchive.shared.snapshot()
            let missing = pack.lessons.contains { snapshot["edu:" + $0.slug] == nil } || snapshot["edu:@profile"] == nil
            if !LessonPaths.offlineReadOnly && missing {
                let remote = try await Api.archiveSnapshot()
                for key in pack.lessons.map({ "edu:" + $0.slug }) + ["edu:@profile"] where snapshot[key] == nil {
                    snapshot[key] = remote[key]
                }
            }
            digest = ReviewDigest.make(book: WrongBook.parse(archive: snapshot, pack: pack),
                                       profile: GrowthProfile.parse(archive: snapshot))
        } catch {
            // 读不到就不显示数字（列表那边会说明原因），不拿 0 冒充
            digest = nil
        }
    }
}

enum HomeSection: Int, CaseIterable, Identifiable, Hashable {
    // rawValue 与 iPhone 标签页的 `-tab` 编号一致（0 错题本 / 1 导入 / 2 复习）；侧栏按 allCases 的顺序排
    case library = 0, review = 2, importing = 1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .library: return "错题本"
        case .review: return "复习"
        case .importing: return "导入"
        }
    }
    var icon: String {
        switch self {
        case .library: return "book.closed"
        case .review: return "arrow.clockwise"
        case .importing: return "square.and.arrow.down"
        }
    }
}

/// 侧栏里的「今天」：今天做了几题（进度条）、连续几天、待巩固几类。用系统语义色，Vision Pro 的玻璃上也读得清。
private struct TodayCard: View {
    let digest: ReviewDigest?

    var body: some View {
        if let d = digest {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(d.done())").font(.title2.weight(.semibold)).monospacedDigit()
                    Text("/ \(d.goal) 题").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Label("连续 \(d.streak) 天", systemImage: "flame.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ProgressView(value: d.progress())
                Text(d.remaining() == 0 ? "今天的题做完了 · 待巩固 \(d.due) 类" : "还差 \(d.remaining()) 题 · 待巩固 \(d.due) 类")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            Text("同步后显示今天的进度").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 错题本 / 复习：左边列表（同一个 FocusLibraryView），右边题目（同一个 LessonScreen）。
private struct LibraryBoard: View {
    let reviewOnly: Bool
    @Binding var selection: ReviewTarget?
    let digest: ReviewDigest?

    var body: some View {
        HStack(spacing: 0) {
            FocusLibraryView(reviewOnly: reviewOnly, selection: $selection)
                .frame(width: 410)
                .id(reviewOnly)                 // 错题本与复习各自一份筛选状态
            Divider()
            Group {
                if let t = selection {
                    LessonScreen(lesson: t.lesson, entry: t.entry, subtitle: t.subtitle,
                                 onClose: { selection = nil })
                        .id(t.id)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.card)
        }
        .paperPanel()
    }

    /// 没选题时：今天的摘要 + 「先复习这几类」（与 Apple Watch 第二页同一份），点一下直接在右边开。
    private var placeholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Ink.accent)
                    Text(reviewOnly ? "选一类开始复习" : "选一道题打开")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Ink.text)
                    Text(reviewOnly ? "做完一组再回来，列表会按练习结果更新。" : "左边是收进来的题，点一道就在这里练。")
                        .font(.callout).foregroundStyle(Ink.dim)
                }
                if let d = digest {
                    HStack(spacing: 12) {
                        stat("\(d.due)", "类待巩固", Ink.red)
                        stat("\(d.done())/\(d.goal)", "今天已做", Ink.accent)
                        stat("\(d.streak)", "天连续", Ink.blue)
                    }
                    if !d.next.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("先复习这几类").font(.headline).foregroundStyle(Ink.text).padding(.bottom, 8)
                            ForEach(d.next) { item in nextRow(item) }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Ink.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.line))
    }

    private func nextRow(_ item: ReviewDigest.Item) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 12) {
                Text(item.subject.prefix(1)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.accent).frame(width: 28, height: 28)
                    .background(Ink.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.text)
                    Text(item.question.isEmpty ? item.lesson : item.question)
                        .font(.caption).foregroundStyle(Ink.dim).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(item.wrongText).font(.caption).foregroundStyle(Ink.red)
                if let ok = item.okText { Text(ok).font(.caption).foregroundStyle(Ink.green) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 摘要里的一类 → 和错题本那一行同一个入口：这一课的「只练这一类」（照片导入的题是原题）。
    private func open(_ item: ReviewDigest.Item) {
        guard let cut = item.id.firstIndex(of: "#") else { return }
        let slug = String(item.id[..<cut]), gid = String(item.id[item.id.index(after: cut)...])
        guard let lesson = LessonPack.load().lessons.first(where: { $0.slug == slug }) else { return }
        selection = ReviewTarget(lesson: lesson, entry: .drill(gid: gid),
                                 subtitle: gid.hasPrefix("photo:") ? "导入原题" : "同类题复习")
    }
}
