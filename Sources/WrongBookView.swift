import SwiftUI

/// 错题本 —— 两层，照抄 `~/Edu` 的语义，不自创第三种。
///
/// | 层 | 是什么 | 点了会怎样 |
/// |---|---|---|
/// | **题型层**（`gid`） | 「这一类题错过 N 次 / 订正 M 次」 | 出**同类新题**，不是重放原题 |
/// | **具体题层**（`hits`） | 「我当时错的是这几道」 | **只读回看**，展开看得见，点不动 |
///
/// 用户原话：「为了防止记住答案，错的题目也要变下」。原题再放一遍只会让孩子把答案
/// 背下来，看着会了其实没会。所以连**数据结构里都没有** `ans` / `options`
/// （见 `WrongEntry`）—— 想重放也放不出来。
///
/// 这一屏**不写任何东西**。收进错题本、连着订正 2 次划掉，都是练习引擎干的；
/// 这里读的就是它写的那一份（`EduArchive`）。原生要是也能改，两边迟早说不同的话。
struct WrongBookView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let pack = LessonPack.load()
    @State private var book = WrongBook.unread
    @State private var loading = true
    @State private var problem: String?
    @State private var expanded: Set<String> = []
    @State private var open: ReviewTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let p = problem {
                        banner(p, Ink.red)
                    } else if loading {
                        ProgressView().tint(Ink.red)
                            .frame(maxWidth: .infinity).padding(.top, 50)
                    } else if book.byLesson.isEmpty {
                        empty
                    } else {
                        tip
                        ForEach(book.byLesson) { g in section(g) }
                    }
                    if !book.orphanSlugs.isEmpty {
                        banner("存档里还有 \(book.orphanSlugs.count) 课的错题，但这一版包里没有这些课："
                               + book.orphanSlugs.joined(separator: "、"), Ink.blue)
                    }
                }
                .padding(18)
            }
            .background(Ink.paper)
            .navigationTitle(book.totalTypes > 0 ? "错题本 · \(book.totalTypes) 类" : "错题本")
        }
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await reload() } } }
        .fullScreenCover(item: $open, onDismiss: { Task { await reload() } }) { t in
            LessonScreen(lesson: t.lesson, entry: t.entry, subtitle: t.subtitle)
        }
    }

    private var tip: some View {
        Text("复习出的是**同类新题**，不是原题 —— 连着一次做对 2 回才划掉。")
            .font(.footnote).foregroundStyle(Ink.dim)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("错题本是空的").font(.headline).foregroundStyle(Ink.text)
            Text("做题时同一道连错两次会自动收进来；也可以在题目页点「☆ 收进错题本」手动收一类。\n"
                 + "连着订正 2 次才划掉 —— 一次蒙对不算学会。")
                .font(.footnote).foregroundStyle(Ink.dim)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1))
    }

    private func section(_ g: LessonWrongs) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(g.lesson.title).font(.title3.weight(.heavy)).foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Button {
                    open = ReviewTarget(lesson: g.lesson, entry: .wrongSet, subtitle: "错题卷")
                } label: {
                    Text("组一套错题卷").font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.blue)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Ink.blue.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(g.entries) { e in row(g.lesson, e) }
        }
    }

    private func row(_ lesson: Lesson, _ e: WrongEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(e.gname).font(.headline).foregroundStyle(Ink.text)
                    HStack(spacing: 8) {
                        Text(e.wrongText).font(.caption).foregroundStyle(Ink.red)
                        if let o = e.okText {
                            Text(o).font(.caption.weight(.semibold)).foregroundStyle(Ink.green)
                        }
                        if !e.at.isEmpty {
                            Text(e.at).font(.caption).foregroundStyle(Ink.dim)
                        }
                    }
                    if !e.hits.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { toggle(e.id) }
                        } label: {
                            Label("我当时错的那 \(e.hits.count) 道",
                                  systemImage: expanded.contains(e.id)
                                    ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(Ink.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    open = ReviewTarget(lesson: lesson, entry: .drill(gid: e.gid), subtitle: e.gname)
                } label: {
                    Text("复习").font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Ink.red, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if expanded.contains(e.id) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(e.hits.enumerated()), id: \.offset) { _, h in
                        HStack(alignment: .top, spacing: 6) {
                            Text("・").foregroundStyle(Ink.dim.opacity(0.6))
                            Text(h.label).foregroundStyle(Ink.text.opacity(0.85))
                            Spacer(minLength: 0)
                            if !h.at.isEmpty { Text(h.at).foregroundStyle(Ink.dim.opacity(0.7)) }
                        }
                        .font(.caption)
                    }
                    // 说清这里为什么点不动 —— 不然看着像个坏掉的列表
                    Text("只回看，不重做 —— 重做的是上面那颗「复习」，出的是同类新题")
                        .font(.caption2).foregroundStyle(Ink.dim.opacity(0.75))
                        .padding(.top, 2)
                }
                .padding(.top, 10)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1))
    }

    private func banner(_ text: String, _ c: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(c)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(c.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func reload() async {
        problem = nil
        do {
            let snap = try await EduArchive.shared.snapshot()
            book = WrongBook.parse(archive: snap, pack: pack)
        } catch {
            // 「读不到」和「一条错题都没有」长得一模一样 —— 必须分开说
            problem = "读不到存档：\(error.localizedDescription)"
        }
        loading = false
    }
}

/// 从错题本点进去要打开什么。
struct ReviewTarget: Identifiable {
    let lesson: Lesson
    let entry: LessonEntry
    let subtitle: String
    var id: String {
        switch entry {
        case .drill(let gid): return lesson.slug + "#" + gid
        case .wrongSet:       return lesson.slug + "#wrong"
        case .normal:         return lesson.slug
        }
    }
}
