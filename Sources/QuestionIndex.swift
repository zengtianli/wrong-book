import Foundation

/// Read-only projection of authenticated, hash-verified lesson payloads.
/// Answers and mastery remain owned by the shared practice engine.
enum QuestionIndex {
    struct Item: Identifiable {
        let lesson: Lesson
        let uid: String
        let gid: String
        let text: String
        let isPrivate: Bool
        var id: String { lesson.slug + ":" + uid }
    }
    enum IndexError: Error { case unavailable, malformed }
    static func read(_ lesson: Lesson) throws -> [Item] {
        guard let url = lesson.resolvedURL else { throw IndexError.unavailable }
        return try parse(String(contentsOf: url, encoding: .utf8), lesson: lesson)
    }
    static func parse(_ html: String, lesson: Lesson) throws -> [Item] {
        guard let initRange = html.range(of: "PRACTICE.init(", options: .backwards),
              let itemsRange = html.range(of: "items:", range: initRange.upperBound..<html.endIndex),
              let start = html[itemsRange.upperBound...].firstIndex(of: "[") else { throw IndexError.malformed }
        var quoted = false, escaped = false, depth = 0
        var end: String.Index?
        for i in html[start...].indices {
            let c = html[i]
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "[" { depth += 1 }
            else if c == "]" { depth -= 1; if depth == 0 { end = html.index(after: i); break } }
        }
        guard let end, let data = String(html[start..<end]).data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw IndexError.malformed }
        let privateItems = html[end...].range(of: #"privateItems:\s*true"#, options: .regularExpression) != nil
        return rows.compactMap { row in
            guard let uid = row["uid"] as? String, !uid.isEmpty, let q = row["q"] as? String, !q.isEmpty,
                  privateItems || row["own"] as? Int == 1 else { return nil }
            let gid = privateItems ? "photo:" + uid : (row["gid"] as? String ?? "")
            let ask = row["ask"] as? String ?? ""
            return Item(lesson: lesson, uid: uid, gid: gid, text: plain(q + (ask.isEmpty ? "" : " " + ask)), isPrivate: privateItems)
        }
    }
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (from, to) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
