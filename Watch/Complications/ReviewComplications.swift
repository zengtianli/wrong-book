import SwiftUI
import WidgetKit

/// 表盘复杂功能：读手表 App 刷新时写进钥匙串的复习摘要（DigestSnapshot），自己不联网。
/// 手表 App 每次刷新成功都会 reloadAllTimelines；这里只在零点多排一条，把「今天已做」清零。
@main
struct ReviewComplications: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cyou.tianli.wrongbook.review", provider: ReviewProvider()) { entry in
            ReviewComplicationView(digest: entry.digest, date: entry.date)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(String(localized: "app.name"))
        .description("待巩固几类、今天做了几题、连续几天。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ReviewEntry: TimelineEntry {
    let date: Date
    let digest: ReviewDigest?
}

struct ReviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviewEntry {
        ReviewEntry(date: Date(), digest: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReviewEntry) -> Void) {
        // 表盘编辑器里的预览：没有真实数据时给占位形状，不给空白
        completion(ReviewEntry(date: Date(), digest: DigestSnapshot.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReviewEntry>) -> Void) {
        let now = Date(), digest = DigestSnapshot.load()
        var entries = [ReviewEntry(date: now, digest: digest)]
        if let digest, digest.dayEnd > now { entries.append(ReviewEntry(date: digest.dayEnd, digest: digest)) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

extension ReviewDigest {
    /// 表盘编辑器里的占位形状（会被系统打码，数字只为撑出版式）
    static let placeholder = ReviewDigest(due: 6, doneToday: 7, goal: 12, streak: 6, level: 5,
                                          dayEnd: .distantFuture, next: [], updated: Date())
}
