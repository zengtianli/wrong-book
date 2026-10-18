import Foundation

/// A personal library describes existing content, not which subjects a user may import next.
/// Preserve the app's existing Chinese/math choices even when the library contains only one.
enum ImportSubjectOptions {
    typealias Choice = (key: String, name: String)

    static func merging(_ librarySubjects: [Choice]) -> [Choice] {
        var choices: [Choice] = [("chinese", String(localized: "语文")), ("math", String(localized: "数学"))]
        for subject in librarySubjects {
            guard !subject.key.isEmpty else { continue }
            let title = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = choices.firstIndex(where: { $0.key == subject.key }) {
                if !title.isEmpty {
                    // Canonical subject names are UI copy; custom library names are user data.
                    switch (subject.key, title) {
                    case ("chinese", "语文"): choices[index].name = String(localized: "语文")
                    case ("math", "数学"): choices[index].name = String(localized: "数学")
                    default: choices[index].name = title
                    }
                }
            } else {
                choices.append((subject.key, title.isEmpty ? subject.key : title))
            }
        }
        return choices
    }
}
