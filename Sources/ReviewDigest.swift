import Foundation

/// 抬腕 / 侧栏那一眼要看的复习摘要：待巩固几类、今天做了几题、连续几天、先复习哪几类。
///
/// **全部从引擎写的存档现算**（`ReviewDigest.make`，在 WrongBook.swift 里，读 `WrongBook` / `GrowthProfile`），
/// 不另记一份 —— 和错题本「复习」那一页同一个来源，所以 iPad 侧栏、Apple Watch 与表盘复杂功能上的数字对得上。
/// 这个文件只有数据形状：表盘复杂功能只编它（不碰存档解析、不联网）。存进手表钥匙串的也只有这几个数和
/// 题面摘要 —— 结构里没有答案。
struct ReviewDigest: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        /// `<slug>#<gid>`
        let id: String
        /// 题型名（「分数比较大小」）
        let name: String
        /// 课名
        let lesson: String
        let subject: String
        /// 上次错的那道的题面摘要（引擎那边 ≤60 字）
        let question: String
        let wrong: Int
        let ok: Int
        let manual: Bool

        /// 与 WrongEntry 同一种说法：错几次是红的一截，订正进度是绿的一截
        var wrongText: String { manual && wrong == 0 ? String(localized: "手动收进") : String(localized: "错 \(wrong) 次") }
        var okText: String? { ok > 0 ? String(localized: "已订正 \(ok)/2") : nil }
    }

    /// 待巩固几类（= 错题本里还没连对两次划掉的题型数，「复习」那一页的来源）
    let due: Int
    /// 取数那天已做几题 —— 过了 `dayEnd` 就不算数（见 `done(on:)`）
    let doneToday: Int
    let goal: Int
    let streak: Int
    let level: Int
    /// 取数那天的结束时刻（本地次日零点）
    let dayEnd: Date
    /// 先复习这几类：还没订正过的在前，错得多的在前，同样多时旧的在前
    let next: [Item]
    let updated: Date

    static let limit = 5

    /// 某一刻的「今天已做」：摘要是昨天取的，过了零点就当今天一题没做（与 GrowthProfile.parse 跨天清零同一条规则）。
    func done(on date: Date = Date()) -> Int { date < dayEnd ? doneToday : 0 }

    func remaining(on date: Date = Date()) -> Int { max(0, goal - done(on: date)) }

    /// 今天的进度（0…1），给圆环用
    func progress(on date: Date = Date()) -> Double {
        goal > 0 ? min(1, Double(done(on: date)) / Double(goal)) : 0
    }
}
