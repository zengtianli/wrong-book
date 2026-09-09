import Foundation

// The parser reads the real renderer output. File authorization remains in Lesson.resolvedURL.
struct Lesson {
    let slug = "isolated-fixture"
    let resolvedURL: URL? = nil
}

@main
struct QuestionIndexRegression {
    static func main() throws {
        let lesson = Lesson()
        let html = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let items = try QuestionIndex.parse(html, lesson: lesson)
        precondition(items.count == 2, "All renderer questions must be indexed")
        precondition(items.allSatisfy { $0.isPrivate && $0.gid == "photo:" + $0.uid })
        precondition(items[0].text.contains("12 + 8"))
        precondition(items[1].text.contains("["), "Brackets inside text must not truncate the array")
        precondition(Set(items.map(\.id)).count == 2)
        let legacy = #"PRACTICE.init({ items: [{"uid":"sample","own":0,"q":"sample"},{"uid":"own","own":1,"gid":"g1","q":"<b>Keep</b> &amp; review"}], gens: [], privateItems: false });"#
        let own = try QuestionIndex.parse(legacy, lesson: lesson)
        precondition(own.count == 1 && own[0].gid == "g1" && own[0].text == "Keep & review")
        for malformed in ["", "PRACTICE.init({items: [", "PRACTICE.init({items: [not-json]})"] {
            do { _ = try QuestionIndex.parse(malformed, lesson: lesson); fatalError("Malformed payload accepted") }
            catch {}
        }
        do { _ = try QuestionIndex.read(lesson); fatalError("Unavailable file accepted") } catch {}
        print("PASS real renderer: both questions, stable IDs, private drill mapping")
        print("PASS escaped brackets, legacy own/sample filtering, HTML text, malformed and unavailable input")
    }
}
