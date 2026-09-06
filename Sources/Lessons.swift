import Foundation

/// Personal lessons returned by the authenticated account-scoped manifest.
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
    var scope: String = ""

    var id: String { slug }
    var isTeach: Bool { kind == "teach" }

    /// Only the current account instance can resolve this validated local file.
    var resolvedURL: URL? {
        guard !scope.isEmpty, scope == LessonPaths.activeScope, LessonPaths.valid(file),
              let root = LessonPaths.downloads else { return nil }
        let d = root.appendingPathComponent(file)
        guard let bytes = try? Data(contentsOf: d), bytes.sha256Hex == sha256 else { return nil }
        return d
    }

    /// 现在跑的是下载来的新版还是随包发的那版 —— 给界面标一下，也给排查用
    var isUpdated: Bool {
        resolvedURL != nil
    }
}

/// Current authenticated personal library; a new account is legitimately empty.
struct LessonPack {
    let lessons: [Lesson]
    let dailyGoal: Int
    /// 组装器缺席 / manifest 读不动时的原因，给界面显示 —— 不是静默空列表。
    let problem: String?

    static let empty = LessonPack(lessons: [], dailyGoal: 12,
                                  problem: nil)

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
        guard let scope = LessonPaths.activeScope, let root = LessonPaths.downloads,
              let d = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              o["scope"] as? String == scope else { return .empty }
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
                   sha256: j["sha256"] as? String ?? "", scope: scope)
        }
        // A new personal library is intentionally empty.
        if list.isEmpty {
            return LessonPack(lessons: [], dailyGoal: o["daily_goal"] as? Int ?? 12,
                              problem: nil)
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
