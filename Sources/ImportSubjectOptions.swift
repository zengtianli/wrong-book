import Foundation

/// A personal library describes existing content, not which subjects a user may import next.
/// Preserve the app's existing Chinese/math choices even when the library contains only one.
enum ImportSubjectOptions {
    typealias Choice = (key: String, name: String)

    static func merging(_ librarySubjects: [Choice]) -> [Choice] {
        var choices: [Choice] = [("chinese", "语文"), ("math", "数学")]
        for subject in librarySubjects {
            guard !subject.key.isEmpty else { continue }
            let title = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = choices.firstIndex(where: { $0.key == subject.key }) {
                if !title.isEmpty { choices[index].name = title }
            } else {
                choices.append((subject.key, title.isEmpty ? subject.key : title))
            }
        }
        return choices
    }
}
