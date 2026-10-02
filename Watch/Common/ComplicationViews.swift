import SwiftUI
import WidgetKit

/// 手表上的配色：错题本的墨绿（Ink.accent）在黑底上太暗，按同一色相提亮；红 / 绿两截的含义与 iPhone 相同。
enum WatchInk {
    static let accent = Color(hex: 0x5DBB8F)
    static let deep = Color(hex: 0x1F4D3E)
    static let red = Color(hex: 0xF08A7E)
    static let ok = Color(hex: 0x86D9AE)
    static let flame = Color(hex: 0xF5A35C)
}

/// 表盘复杂功能的四种尺寸（表盘上由 WidgetKit 按 family 选；手表 App 的 `-complications 1` 验证页直接摆出四个）。
/// 只读摘要，不联网。`digest == nil` = 还没在手表上登录过（或 iPhone 已退出）。
struct ReviewComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let digest: ReviewDigest?
    var date = Date()

    var body: some View {
        switch family {
        case .accessoryRectangular: ReviewRectangular(digest: digest, date: date)
        case .accessoryInline: ReviewInline(digest: digest, date: date)
        case .accessoryCorner: ReviewCorner(digest: digest, date: date)
        default: ReviewCircular(digest: digest, date: date)
        }
    }
}

/// 圆形：圈 = 今天做了几题 / 目标，圈心 = 待巩固几类。
struct ReviewCircular: View {
    let digest: ReviewDigest?
    var date = Date()

    var body: some View {
        if let d = digest {
            Gauge(value: Double(d.done(on: date)), in: 0...Double(max(d.goal, 1))) {
                Image(systemName: "book.closed")
            } currentValueLabel: {
                Text("\(d.due)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(WatchInk.accent)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "book.closed").font(.title3)
            }
        }
    }
}

/// 矩形：待巩固几类 / 先复习哪一类 / 今天进度与连续天数。
struct ReviewRectangular: View {
    let digest: ReviewDigest?
    var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(digest.map { "待巩固 \($0.due) 类" } ?? "错题本", systemImage: "book.closed.fill")
                .font(.headline)
                .widgetAccentable()
            if let d = digest {
                Text(d.next.first.map { "先复习：\($0.name)" } ?? "错题都订正完了")
                    .lineLimit(1)
                Text("今天 \(d.done(on: date))/\(d.goal) 题 · 连续 \(d.streak) 天")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("在 iPhone 上登录后显示").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 单行（表盘顶部那一行文字）。
struct ReviewInline: View {
    let digest: ReviewDigest?
    var date = Date()

    var body: some View {
        if let d = digest {
            Label("待巩固 \(d.due) · 今天 \(d.done(on: date))/\(d.goal)", systemImage: "book.closed")
        } else {
            Label("错题本", systemImage: "book.closed")
        }
    }
}

/// 表角：角里是待巩固几类，弧上是今天的进度。
struct ReviewCorner: View {
    let digest: ReviewDigest?
    var date = Date()

    var body: some View {
        if let d = digest {
            Text("\(d.due)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: Double(d.done(on: date)), in: 0...Double(max(d.goal, 1))) {
                        Text("今天")
                    } currentValueLabel: {
                        Text("\(d.done(on: date))")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("\(d.goal)")
                    }
                    .tint(WatchInk.accent)
                }
        } else {
            Image(systemName: "book.closed").font(.title3)
                .widgetLabel("错题本")
        }
    }
}
