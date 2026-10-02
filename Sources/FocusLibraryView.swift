import SwiftUI

struct FocusLibraryView: View {
    @EnvironmentObject var sync: LessonSync
    @Environment(\.scenePhase) private var phase
    var reviewOnly = false
    /// 宽屏（iPad / Mac / Vision Pro）：点一道题不弹全屏，而是交给右边的题目栏（RegularHomeView 的 LibraryBoard）。
    /// 窄屏传 nil，行为与原来逐字相同。
    var selection: Binding<ReviewTarget?>? = nil
    @State private var pack = LessonPack.empty
    @State private var items: [QuestionIndex.Item] = []
    @State private var book = WrongBook.unread
    @State private var subject = ""
    @State private var search = ""
    @State private var pendingOnly = false
    @State private var loading = true
    @State private var problem: String?
    @State private var open: ReviewTarget?
    #if DEBUG
    @State private var openedLaunchQuestion = false
    #endif
    @FocusState private var searchFocused: Bool

    private var visible: [QuestionIndex.Item] {
        items.filter { item in
            (subject.isEmpty || item.lesson.subject == subject)
            && ((!reviewOnly && !pendingOnly) || pending(item))
            && (search.isEmpty || (item.text + item.lesson.title + item.lesson.subjectName).localizedCaseInsensitiveContains(search))
        }
    }
    private func pending(_ item: QuestionIndex.Item) -> Bool {
        book.byLesson.first { $0.lesson.slug == item.lesson.slug }?.entries.contains { $0.gid == item.gid } == true
    }
    private var fallback: [Lesson] {
        pack.lessons.filter { l in
            !l.isTeach && ["math", "chinese", "english"].contains(l.subject) && !items.contains { $0.lesson.slug == l.slug }
            && (subject.isEmpty || subject == l.subject)
            && ((!reviewOnly && !pendingOnly) || book.byLesson.contains { $0.lesson.slug == l.slug })
            && (search.isEmpty || (l.title + l.desc).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        Group {
            if selection != nil {
                library
            } else {
                #if os(iOS)
                library.fullScreenCover(item: $open, onDismiss: { Task { await reload() } }) { target in
                    LessonScreen(lesson: target.lesson, entry: target.entry, subtitle: target.subtitle)
                }
                #else
                if let target = open {
                    LessonScreen(lesson: target.lesson, entry: target.entry, subtitle: target.subtitle,
                                 onClose: { open = nil; Task { await reload() } }).id(target.id)
                } else { library }
                #endif
            }
        }
        .task { await reload() }
        .onChange(of: sync.revision) { _, _ in Task { await reload() } }
        .onChange(of: phase) { _, p in if p == .active { Task { await reload() } } }
        // 宽屏：右边的题目关掉了 = 做完一组回来，和窄屏关全屏时一样重读一次待巩固
        .onChange(of: selection?.wrappedValue?.id) { old, new in
            if old != nil, new == nil { Task { await reload() } }
        }
    }
    /// 点开一道题：窄屏弹全屏（iPhone）/ 原地换成题目（窄 Mac 窗口），宽屏交给右边的题目栏。
    private func choose(_ target: ReviewTarget) {
        if let selection { selection.wrappedValue = target } else { open = target }
    }
    private func isSelected(_ id: String) -> Bool { selection?.wrappedValue?.id == id }
    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(reviewOnly ? "REVIEW & UNDERSTAND" : "MY WRONGBOOK")
                        .font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Ink.accent)
                    Text(reviewOnly ? "复习，把它真正学会" : "我的错题本")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Ink.text)
                    Text(reviewOnly ? "从待巩固的题开始，做完一组再回看。" : "把没弄明白的题留下来，一道一道学会。")
                        .font(.caption).foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 4)
                if !reviewOnly {
                    Button { NotificationCenter.default.post(name: .wrongbookImport, object: nil) } label: { Label("导入", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Picker("学科", selection: $subject) {
                    Text("全部科目").tag("")
                    ForEach(pack.tree.filter { ["math", "chinese", "english"].contains($0.key) }) { group in Text(group.name).tag(group.key) }
                }.labelsHidden().pickerStyle(.menu).wideFixedSize()
                if !reviewOnly { Toggle("待巩固", isOn: $pendingOnly).toggleStyle(.button).controlSize(.small) }
                Spacer(minLength: 0)
                Text("\(visible.count) 道").font(.caption).foregroundStyle(Ink.dim)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.dim)
                #if os(visionOS)
                // Vision Pro 的占位字是给玻璃底配的浅色，摊在白纸上看不见：显式给一个深一点的
                TextField("搜索题目或来源", text: $search, prompt: Text("搜索题目或来源").foregroundStyle(Ink.dim))
                    .textFieldStyle(.plain).focused($searchFocused)
                #else
                TextField("搜索题目或来源", text: $search).textFieldStyle(.plain).focused($searchFocused)
                #endif
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line))
                .background(Button("") { searchFocused = true }.keyboardShortcut("k", modifiers: .command).hidden())
            if let problem { Label(problem, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Ink.red) }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in questionRow(item) }
                    ForEach(fallback) { lesson in
                        Button { choose(ReviewTarget(lesson: lesson, entry: reviewOnly ? .wrongSet : .normal, subtitle: "练习资料")) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(lesson.title).font(.system(size: 14)).foregroundStyle(Ink.text)
                                    Text("练习资料 · 打开查看题目").font(.caption).foregroundStyle(Ink.dim)
                                }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.dim)
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .selectedRow(isSelected(lesson.slug + (reviewOnly ? "#wrong" : "")))
                        Divider()
                    }
                    if !loading && visible.isEmpty && fallback.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: reviewOnly ? "checkmark.circle" : "book.closed").font(.system(size: 28)).foregroundStyle(Ink.accent)
                            Text(reviewOnly ? "暂无待巩固的题" : "从第一道错题开始").font(.headline)
                            Text(search.isEmpty ? "导入自己的图片，识别后同步到这里。" : "没有符合条件的题目，试试其他关键词。")
                                .font(.caption).foregroundStyle(Ink.dim)
                            Button("导入图片") { NotificationCenter.default.post(name: .wrongbookImport, object: nil) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                }.background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.line))
            }.refreshable { await sync.sync(force: true); await reload() }
            Text("已同步资料可离线练习 · 掌握进度由练习结果更新").font(.system(size: 10)).foregroundStyle(Ink.dim)
        }.padding(20).background(Ink.paper)
    }
    private func questionRow(_ item: QuestionIndex.Item) -> some View {
        VStack(spacing: 0) {
            Button { choose(ReviewTarget(lesson: item.lesson, entry: item.gid.isEmpty ? .normal : .drill(gid: item.gid),
                                         subtitle: item.isPrivate ? "导入原题" : "同类题复习")) } label: {
                HStack(spacing: 12) {
                    Text(item.lesson.subjectName.prefix(1)).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.accent).frame(width: 28, height: 28)
                        .background(Ink.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.text).font(.system(size: 14)).foregroundStyle(Ink.text).lineLimit(2).multilineTextAlignment(.leading)
                        Text(item.lesson.title + " · " + item.lesson.date).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if pending(item) { Text("待巩固").font(.system(size: 10)).foregroundStyle(Ink.red) }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ink.dim)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .selectedRow(isSelected(item.lesson.slug + (item.gid.isEmpty ? "" : "#" + item.gid)))
            Divider().padding(.leading, 52)
        }
    }
    @MainActor private func reload() async {
        let scope = LessonPaths.activeScope, loaded = LessonPack.load()
        var rows: [QuestionIndex.Item] = [], failed = false
        for lesson in loaded.lessons where !lesson.isTeach && ["math", "chinese", "english"].contains(lesson.subject) {
            do { rows += try QuestionIndex.read(lesson) } catch { failed = true }
        }
        var updatedBook = WrongBook.unread, note = loaded.problem
        do {
            var snapshot = try await EduArchive.shared.snapshot()
            if !LessonPaths.offlineReadOnly && loaded.lessons.contains(where: { snapshot["edu:" + $0.slug] == nil }) {
                let remote = try await Api.archiveSnapshot()
                // Prefer the engine's local state; never replace unsynced practice.
                for lesson in loaded.lessons where snapshot["edu:" + lesson.slug] == nil {
                    snapshot["edu:" + lesson.slug] = remote["edu:" + lesson.slug]
                }
            }
            updatedBook = WrongBook.parse(archive: snapshot, pack: loaded)
        }
        catch { note = "复习进度暂时无法读取，请稍后同步重试。" }
        guard scope == LessonPaths.activeScope else { return }
        pack = loaded; items = rows; book = updatedBook; loading = false
        problem = note ?? (failed ? "部分资料暂时不能逐题列出，可从下方打开原练习。" : nil)
        // 平台验收车道：个人课程同步到位（scope 生效）后列表第一次读完 —— 有数据或明确为空 —— 才算「第一屏有数据」；
        // 登录后、同步前那一次空读不算。不传 -lane_* 时只是一行日志
        if scope != nil { LaneSignal.ready(reviewOnly ? "review" : "library") }
        #if DEBUG
        if !openedLaunchQuestion, let uid = UserDefaults.standard.string(forKey: "library.openQuestion"),
           let item = rows.first(where: { $0.uid == uid }) {
            openedLaunchQuestion = true
            choose(ReviewTarget(lesson: item.lesson, entry: item.gid.isEmpty ? .normal : .drill(gid: item.gid),
                                subtitle: item.isPrivate ? "导入原题" : "同类题复习"))
        }
        #endif
    }
}

private extension View {
    /// 宽屏里正打开着的那一行（淡绿底）；窄屏永远是 false，原样返回。
    @ViewBuilder
    func selectedRow(_ on: Bool) -> some View {
        if on { self.background(Ink.accentSoft) } else { self }
    }
}
