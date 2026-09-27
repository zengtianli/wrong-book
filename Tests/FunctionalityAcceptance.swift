import Foundation

// Isolate file location from account authorization and the SwiftUI library store.
// The parser and file read below are the unmodified production QuestionIndex.
struct Lesson {
    let slug: String
    let resolvedURL: URL?
}

@main
struct FunctionalityAcceptance {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrongbook-functionality-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lesson.html")
        let lesson = Lesson(slug: "synthetic-math", resolvedURL: url)

        // Synthetic renderer-shaped content contains no personal questions or credentials.
        let html = #"""
        <html><body><script>
        // Earlier initialization must not shadow the current lesson payload.
        PRACTICE.init({items: [], privateItems: false});
        PRACTICE.init({items: [
          {"uid":"q1","q":"<b>12 + 8</b>","ask":"结果是多少？"},
          {"uid":"q2","q":"范围 [1, 2] 与 \"引用\" &amp; 符号","ask":"选择答案"},
          {"uid":"","q":"invalid"},
          {"uid":"empty-question","q":""}
        ], gens: [], privateItems: true});
        </script></body></html>
        """#
        try html.write(to: url, atomically: true, encoding: .utf8)
        let items = try QuestionIndex.read(lesson)
        precondition(items.count == 2, "Only valid personal questions should be indexed")
        precondition(items.map(\.id) == ["synthetic-math:q1", "synthetic-math:q2"])
        precondition(items.map(\.gid) == ["photo:q1", "photo:q2"], "Review must address the original photo question")
        precondition(items.allSatisfy(\.isPrivate))
        precondition(items[0].text == "12 + 8 结果是多少？")
        precondition(items[1].text == "范围 [1, 2] 与 \"引用\" & 符号 选择答案")
        let repeated = try QuestionIndex.read(lesson)
        precondition(repeated.map(\.id) == items.map(\.id), "Reread must preserve review identity")

        let legacy = #"PRACTICE.init({items: [{"uid":"sample","own":0,"q":"sample"},{"uid":"own","own":1,"gid":"g1","q":"<b>Keep</b> &amp; review"}], gens: [], privateItems: false});"#
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        let own = try QuestionIndex.read(lesson)
        precondition(own.count == 1 && own[0].gid == "g1" && own[0].text == "Keep & review")
        precondition(!own[0].isPrivate && own[0].id == "synthetic-math:own")

        print("PASS local production file read: 2 valid personal questions, stable review IDs, escaped text, prompt inclusion")
        print("PASS legacy lesson replacement: sample filtering and original generator mapping")
        print("NOT COVERED: authenticated library authorization, iOS UI, import upload/AI, live practice engine, sync and StoreKit")
    }
}
