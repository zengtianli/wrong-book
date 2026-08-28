import SwiftUI

/// 学习路径 —— 学科 → 课，从 bundle/下载来的 manifest 派生
///（manifest 又从 `~/Edu/curriculum.yaml` 经 `curriculum.py` 派生）。
///
/// **这一屏不判断哪一课该不该出现。** curriculum 说有几课就是几课。
/// 在这里再筛一遍就是第二份判据，而两份判据迟早说不同的话。
struct LearnView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var sync: LessonSync

    @State private var pack = LessonPack.load()
    @State private var open: Lesson?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let p = pack.problem { banner(p, Ink.red) }
                    if let n = sync.note { banner(n, Ink.blue) }
                    ForEach(pack.tree) { g in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(g.name)
                                .font(.title2.weight(.heavy)).foregroundStyle(Ink.text)
                            ForEach(g.units) { u in
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(u.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Ink.dim)
                                    ForEach(u.lessons) { l in
                                        Button { open = l } label: { card(l) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    Text("\(pack.lessons.count) 课 · 每天目标 \(pack.dailyGoal) 题 · 没网也能做")
                        .font(.caption).foregroundStyle(Ink.dim)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                }
                .padding(18)
            }
            .background(Ink.paper)
            .navigationTitle("学习")
        }
        // 从课里出来可能下载了新版 / 存档变了，重读一次清单
        .fullScreenCover(item: $open, onDismiss: { pack = LessonPack.load() }) { l in
            LessonScreen(lesson: l)
        }
    }

    private func card(_ l: Lesson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 图标跟着 curriculum 走（每一课自己的 icon），不在这儿写第二份
            Text(l.icon.isEmpty ? (l.isTeach ? "💡" : "✏️") : l.icon).font(.title2)
            VStack(alignment: .leading, spacing: 5) {
                Text(l.title).font(.headline).foregroundStyle(Ink.text)
                if !l.desc.isEmpty {
                    Text(l.desc).font(.caption).foregroundStyle(Ink.dim)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    if l.isTeach { chip("互动精讲 · 不出题", Ink.blue) }
                    if !l.tag.isEmpty { chip(l.tag, Ink.blue) }    // 「第 N 站 · 重点」
                    if !l.date.isEmpty { chip(l.date, Ink.dim) }   // 日期 SSOT 在 .practice.md
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold)).foregroundStyle(Ink.dim.opacity(0.5))
                .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1))
    }

    private func chip(_ s: String, _ c: Color) -> some View {
        Text(s).font(.caption2).foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.10), in: Capsule())
    }

    private func banner(_ t: String, _ c: Color) -> some View {
        Label(t, systemImage: "info.circle.fill")
            .font(.footnote).foregroundStyle(c)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(c.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 做题屏 —— 一整屏交给引擎，原生只留一条薄顶栏（退出 + 课名）。
///
/// 顶栏薄是有意的：练习页自己有题号条、任务条、等级条、勋章墙，
/// 原生再叠一层导航就会把它们挤下去。
struct LessonScreen: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson
    var entry: LessonEntry = .normal
    /// 从错题本进来时顶栏的副标题（题型名），让孩子知道现在在练什么
    var subtitle: String = ""

    @State private var complaint: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline) }
                    .foregroundStyle(Ink.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.title).font(.headline).foregroundStyle(Ink.text).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption2).foregroundStyle(Ink.dim).lineLimit(1)
                    }
                }
                Spacer()
                if lesson.isUpdated {
                    Text("已更新").font(.caption2).foregroundStyle(Ink.green)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Ink.paper)
            Divider()

            // 复习组不出来时必须说 —— 静默给一套普通题，孩子以为在补错题，其实没有
            if let c = complaint {
                Label(c, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Ink.text)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.redSoft)
            }

            LessonWebView(lesson: lesson, entry: entry, onSubmitted: {
                // 交卷了 —— 分是网页自己记的(points_client.js)，这里只把
                // 「今天还能挣 N 分」拉新，不参与算分
                Task { await session.refresh() }
            }, onEntryResult: { r in
                complaint = LessonEntry.complaint(for: r)
            })
            .ignoresSafeArea(edges: .bottom)
        }
        .task { await WebSession.handOff() }     // 把登录 cookie 借给 WebView
    }
}

/// `-lesson <slug>` 的落点 —— 只为验证「离线 / 未登录也能做题」。
struct LessonPreview: View {
    let slug: String
    var drillGid: String? = nil
    private let pack = LessonPack.load()

    var body: some View {
        if let l = pack.lessons.first(where: { $0.slug == slug }) {
            LessonScreen(lesson: l,
                         entry: drillGid.map { LessonEntry.drill(gid: $0) } ?? .normal,
                         subtitle: drillGid ?? "")
        } else {
            // 找不到就说清有哪些 —— 静默白屏会让人以为是 WebView 挂了
            ScrollView {
                Text("包里没有 \(slug)\n\n现有 \(pack.lessons.count) 课：\n"
                     + pack.lessons.map(\.slug).joined(separator: "\n"))
                    .font(.footnote.monospaced()).padding(20)
            }
        }
    }
}
