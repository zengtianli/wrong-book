import Foundation

/// 练习页清单 —— 由 `~/Edu/engine/app_pack.py` 在构建前写进 bundle 的 manifest.json 派生。
///
/// **这个文件里没有任何一课的名字、日期、学科。** 全都从 manifest 读。
/// 写死一份的下场：~/Edu 那边加了课(走 /course)，app 这边要改代码才跟得上，
/// 而漏改不报错 —— 只是那一课不出现在列表里。对账门在 `app_pack.py --check`。
struct Lesson: Identifiable, Hashable {
    /// `practice` = 出题页 / `teach` = 互动精讲页（不出题，「看不懂的时候来这儿」）
    let kind: String
    let slug: String
    let title: String
    let desc: String
    let file: String            // 相对 bundle 的路径，如 primary-math/remainder-basics.html
    let subject: String         // domains.yaml 的 key，如 math / chinese
    let subjectName: String
    let unit: String
    let icon: String
    let date: String
    let source: String
    let tag: String
    let sha256: String

    var id: String { slug }
    var isTeach: Bool { kind == "teach" }

    /// 这一课的页面到底读哪个文件。
    ///
    /// **下载的那份优先**（`LessonSync` 增量更新写进 Application Support 的，
    /// 写之前逐字节校验过 sha256），没有再回落随包发的那份。
    /// 顺序反过来的下场：站上改了课、也下下来了，app 却一直在跑包里的旧版 ——
    /// 不报错，只是孩子做的是上一版的题。
    var resolvedURL: URL? {
        let d = LessonPaths.downloads.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: d.path) { return d }
        return Bundle.main.url(forResource: "Lessons/" + file, withExtension: nil)
    }

    /// 现在跑的是下载来的新版还是随包发的那版 —— 给界面标一下，也给排查用
    var isUpdated: Bool {
        FileManager.default.fileExists(
            atPath: LessonPaths.downloads.appendingPathComponent(file).path)
    }
}

/// bundle 里那一包练习页。**只读**，不做下载、不做缓存 —— 页面随包发（离线是这个 app 存在的理由）。
struct LessonPack {
    let lessons: [Lesson]
    let dailyGoal: Int
    /// 组装器缺席 / manifest 读不动时的原因，给界面显示 —— 不是静默空列表。
    let problem: String?

    static let empty = LessonPack(lessons: [], dailyGoal: 12,
                                  problem: "bundle 里没有练习页（构建时 sync-lessons.sh 没跑？）")

    /// 学科 → 单元 → 课，三层，和 `curriculum.yaml` 一样。
    /// **保持 manifest 的顺序**（那就是学习路径上的先后），不按字典序重排 ——
    /// 「第 1 站」排在「第 5 站」后面就没人看得懂了。
    var tree: [SubjectGroup] {
        var order: [String] = []
        var bucket: [String: [Lesson]] = [:]
        for l in lessons {
            if bucket[l.subject] == nil { order.append(l.subject) }
            bucket[l.subject, default: []].append(l)
        }
        return order.map { k in
            let ls = bucket[k] ?? []
            var uOrder: [String] = []
            var uBucket: [String: [Lesson]] = [:]
            for l in ls {
                if uBucket[l.unit] == nil { uOrder.append(l.unit) }
                uBucket[l.unit, default: []].append(l)
            }
            return SubjectGroup(key: k, name: ls.first?.subjectName ?? k,
                                units: uOrder.map { UnitGroup(name: $0, lessons: uBucket[$0] ?? []) })
        }
    }

    static func load() -> LessonPack {
        // 清单也是「下载的优先」：加了课时，新课只存在于下载来的那一份里。
        // `LessonSync` 是 fail-closed 的 —— 有任何一课没落实就不换清单，
        // 所以这份清单在盘上就意味着「它列的每一课都有页面」。
        let dl = LessonPaths.downloads.appendingPathComponent("manifest.json")
        let src: Data? = (try? Data(contentsOf: dl))
            ?? Bundle.main.url(forResource: "Lessons/manifest", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
        guard let d = src,
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            return .empty
        }
        let raw = (o["lessons"] as? [[String: Any]]) ?? []
        let list = raw.map { j in
            Lesson(kind: j["kind"] as? String ?? "practice",
                   slug: j["slug"] as? String ?? "",
                   title: j["title"] as? String ?? "",
                   desc: j["desc"] as? String ?? "",
                   file: j["file"] as? String ?? "",
                   subject: j["subject"] as? String ?? "",
                   subjectName: j["subject_name"] as? String ?? "",
                   unit: j["unit"] as? String ?? "",
                   icon: j["icon"] as? String ?? "",
                   date: j["date"] as? String ?? "",
                   source: j["source"] as? String ?? "",
                   tag: j["tag"] as? String ?? "",
                   sha256: j["sha256"] as? String ?? "")
        }
        // 空集不静默：manifest 在但一课都没有，是组装出了问题，不是「就这样」
        if list.isEmpty {
            return LessonPack(lessons: [], dailyGoal: o["daily_goal"] as? Int ?? 12,
                              problem: "manifest 里一课都没有")
        }
        // bundle 里真有那个文件吗 —— manifest 说有而文件没进包，表现是「点进去白屏」
        let missing = list.filter { $0.resolvedURL == nil }
        return LessonPack(
            lessons: list,
            dailyGoal: o["daily_goal"] as? Int ?? 12,
            problem: missing.isEmpty ? nil
                : "有 \(missing.count) 课的页面没进包：" + missing.prefix(3).map(\.slug).joined(separator: "、"))
    }
}


struct SubjectGroup: Identifiable {
    let key: String
    let name: String
    let units: [UnitGroup]
    var id: String { key }
}

struct UnitGroup: Identifiable {
    let name: String
    let lessons: [Lesson]
    var id: String { name }
}
