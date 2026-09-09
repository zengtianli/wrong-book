import SwiftUI

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
    var onClose: (() -> Void)? = nil

    @State private var complaint: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { if let onClose { onClose() } else { dismiss() } } label: { Image(systemName: "xmark").font(.headline) }
                    .foregroundStyle(Ink.text)
                    .accessibilityLabel("关闭练习")
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
