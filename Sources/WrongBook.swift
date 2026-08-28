import Foundation

/// 错题本里的**一条 = 一类题**（`gid`），不是一道题。
///
/// 这是 `~/Edu` 定死的语义，原生这边照抄，不自创第三种：
/// 复习时出的是**同类新题**（换数字、换选项、换文本），不是把原题再放一遍 ——
/// 原题重放只会让孩子把答案背下来，看着会了其实没会。
/// 原题面只留一句摘要（`q` / `hits[].q`），供回看「我当时错的是这道」。
///
/// ⚠ **这个结构里没有 `ans`，也没有 `options`** —— 不是忘了写，是不许有。
/// 解析器只认下面这几个字段，所以「原题连答案一起存下来」在结构上就发生不了。
struct WrongEntry: Identifiable, Hashable {
    /// 题型 id。复习时把它交给引擎的 `__PRACTICE__.review(gid)`，由引擎自己出新题。
    let gid: String
    let gname: String
    /// 上次错的那道的题面摘要（≤60 字，引擎那边已经剥过标签）
    let q: String
    let at: String
    /// 错过几次。手动收进来的是 0。
    let wrong: Int
    /// 已经连着订正几次 —— 连着对 2 回才从错题本划掉（一次蒙对不算学会）
    let ok: Int
    let manual: Bool
    /// 具体题层：我当时错的到底是哪几道。**只读回看，不重做。**
    let hits: [WrongHit]

    var id: String { gid }

    /// 「错了几次」—— 永远是红的那一截
    var wrongText: String { manual && wrong == 0 ? "手动收进" : "错 \(wrong) 次" }
    /// 「订正到哪儿了」—— 有进展才有这一截，绿的。两截分开是因为把
    /// 「错 3 次 · 已订正 1/2」整条涂成绿色，看着像这一类已经过关了。
    var okText: String? { ok > 0 ? "已订正 \(ok)/2" : nil }
}

/// 具体题层的一条。`no` 是「卷子第几题」—— 原题才有，生成题为空。
struct WrongHit: Hashable {
    let q: String
    let at: String
    let no: String
    let src: String

    var label: String { no.isEmpty ? q : "卷子第 \(no) 题　\(q)" }
}

/// 一课的错题本。
struct LessonWrongs: Identifiable {
    let lesson: Lesson
    let entries: [WrongEntry]
    var id: String { lesson.slug }
}

/// 整本错题本 = 各课的并集 + 读不出来的原因。
///
/// **来源只有一个**：WebView 里练习引擎写的 localStorage（见 `EduArchive`）。
/// 原生不缓存、不补写、不合并 —— 孩子在页面里划掉一条，这里下次就看不到它，
/// 因为这里读的本来就是同一份。
struct WrongBook {
    let byLesson: [LessonWrongs]
    /// 存档里有 `edu:<slug>` 但 manifest 里没有这一课（课下架了 / 包是旧的）
    let orphanSlugs: [String]
    /// 读失败的原因。非 nil 时界面必须显示 —— 「读不到」和「一条错题都没有」
    /// 长得一模一样，混起来就永远查不出是哪种。
    let problem: String?

    var totalTypes: Int { byLesson.reduce(0) { $0 + $1.entries.count } }

    static let unread = WrongBook(byLesson: [], orphanSlugs: [], problem: nil)

    /// 从存档快照解析。`archive` = `EduArchive.snapshot()` 的原样输出。
    static func parse(archive: [String: String], pack: LessonPack) -> WrongBook {
        let bySlug = Dictionary(uniqueKeysWithValues: pack.lessons.map { ($0.slug, $0) })
        var out: [LessonWrongs] = []
        var orphans: [String] = []

        for (key, raw) in archive {
            guard key.hasPrefix("edu:") else { continue }
            let slug = String(key.dropFirst(4))
            if slug.hasPrefix("@") { continue }              // @profile / @owner / @syncts 不是课
            guard let d = raw.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            let list = (o["wrong"] as? [[String: Any]]) ?? []
            let entries = list.compactMap(entry(from:))
            guard !entries.isEmpty else { continue }
            if let l = bySlug[slug] {
                out.append(LessonWrongs(lesson: l, entries: entries))
            } else {
                orphans.append(slug)
            }
        }
        // 顺序跟着 manifest（= curriculum.yaml 的顺序），不按字典序 ——
        // 学习路径上第几站，错题本里就排第几个
        let order = Dictionary(uniqueKeysWithValues: pack.lessons.enumerated().map { ($1.slug, $0) })
        out.sort { (order[$0.lesson.slug] ?? .max) < (order[$1.lesson.slug] ?? .max) }
        return WrongBook(byLesson: out, orphanSlugs: orphans.sorted(), problem: nil)
    }

    private static func entry(from j: [String: Any]) -> WrongEntry? {
        guard let gid = j["gid"] as? String, !gid.isEmpty else { return nil }
        let hits = ((j["hits"] as? [[String: Any]]) ?? []).map { h in
            // `no`（卷子第几题）在引擎那边有时是字符串有时是数字，两种都要收 ——
            // String(describing:) 会把 NSNull 变成 "<null>" 印到界面上
            let no: String
            if let s = h["no"] as? String { no = s }
            else if let i = h["no"] as? Int { no = String(i) }
            else { no = "" }
            return WrongHit(q: h["q"] as? String ?? "",
                            at: h["at"] as? String ?? "",
                            no: no,
                            src: h["src"] as? String ?? "")
        }
        return WrongEntry(gid: gid,
                          gname: j["gname"] as? String ?? "错题",
                          q: j["q"] as? String ?? "",
                          at: j["at"] as? String ?? "",
                          wrong: j["wrong"] as? Int ?? 0,
                          ok: j["ok"] as? Int ?? 0,
                          manual: (j["manual"] as? Int ?? 0) != 0,
                          hits: hits.filter { !$0.q.isEmpty })
    }
}

/// 今日任务 / 等级 —— 存档里 `edu:@profile` 那一份，原生只读。
struct GrowthProfile {
    let xp: Int
    let level: Int
    let doneToday: Int
    let goal: Int
    let streakDays: Int

    var remaining: Int { max(0, goal - doneToday) }

    /// 等级算法和 `practice.js` 的 `levelOf` 逐行相同（升一级要 80 + (lv-1)*50 经验）。
    /// **这是这个 app 里唯一一处复制了引擎的算法** —— 只为在原生界面上显示一个数字，
    /// 不参与任何判定。真要以它做判断时，改成从引擎里读，别在这儿长出第二套规则。
    static func levelOf(_ xp: Int) -> Int {
        var l = 1, rest = xp
        while l < 99 && rest >= 80 + (l - 1) * 50 { rest -= 80 + (l - 1) * 50; l += 1 }
        return l
    }

    static func parse(archive: [String: String]) -> GrowthProfile? {
        guard let raw = archive["edu:@profile"], let d = raw.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let xp = o["xp"] as? Int ?? 0
        let day = o["day"] as? [String: Any] ?? [:]
        // 跨天了就当今天一题没做 —— 引擎是在下次 pload() 时清零的，
        // 这里若照搬旧值，会在半夜之后显示「今天已做 12 题」，然后通知也就不发了。
        let today = Self.todayStamp()
        let n = (day["d"] as? String) == today ? (day["n"] as? Int ?? 0) : 0
        let days = o["days"] as? [String: Any] ?? [:]
        return GrowthProfile(xp: xp, level: levelOf(xp), doneToday: n,
                             goal: o["goal"] as? Int ?? 12,
                             streakDays: days["streak"] as? Int ?? 0)
    }

    /// 和 `practice.js` 的 `today()` 同一种写法：`2026-8-9`（月/日**不补零**）。
    /// 补了零就永远对不上，表现是「每天都以为跨天了」—— 计数看着总是 0。
    static func todayStamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
