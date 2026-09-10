import Foundation

@main
struct ImportSubjectRegression {
    static func main() {
        let empty = ImportSubjectOptions.merging([])
        precondition(empty.map(\.key) == ["chinese", "math"])

        let chineseOnly = ImportSubjectOptions.merging([("chinese", "语文")])
        precondition(chineseOnly.contains { $0.key == "math" },
                     "An existing Chinese lesson must not prevent the next math import")

        let mathOnly = ImportSubjectOptions.merging([("math", "数学")])
        precondition(mathOnly.contains { $0.key == "chinese" },
                     "The initial Chinese selection must remain a valid picker choice")

        let named = ImportSubjectOptions.merging([("math", " 数学练习 "), ("math", ""), ("", "无效")])
        precondition(named.map(\.key) == ["chinese", "math"], "Choices must remain unique and nonempty")
        precondition(named.first { $0.key == "math" }?.name == "数学练习",
                     "Use the library's title without replacing it with an empty duplicate")

        print("PASS import subjects: empty and single-subject libraries retain both choices; valid titles and unique keys")
    }
}
