import SwiftUI

/// 从错题本点进去要打开什么。
struct ReviewTarget: Identifiable {
    let lesson: Lesson
    let entry: LessonEntry
    let subtitle: String
    var id: String {
        switch entry {
        case .drill(let gid): return lesson.slug + "#" + gid
        case .wrongSet:       return lesson.slug + "#wrong"
        case .normal:         return lesson.slug
        }
    }
}
