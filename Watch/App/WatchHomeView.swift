import SwiftUI

/// 手表主页：上下翻两页。
/// 第一页是抬腕那一眼：待巩固几类（大数字）、今天做了几题（圆环）、连续几天；
/// 第二页是「先复习这几类」：还没订正过的、错得多的在前，和 iPhone 复习页同一份错题本。
struct WatchHomeView: View {
    @EnvironmentObject var store: WatchStore
    // 验证通道：和 iPhone 一样认 `-tab 1`，直接落到第二页（headless 截图翻不了页）。不传就是第一页。
    @State private var page = UserDefaults.standard.integer(forKey: "tab") == 1 ? 1 : 0

    private var d: ReviewDigest? { store.digest }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                glance
                    .containerBackground(WatchInk.deep.gradient, for: .tabView)
                    .tag(0)
                nextPage
                    .containerBackground(WatchInk.deep.gradient, for: .tabView)
                    .tag(1)
            }
            .tabViewStyle(.verticalPage)
        }
        // 主页只在拿到摘要（或上次那份）后才出现：这就是手表上「第一屏有数据」的时刻
        .onAppear { LaneSignal.ready("watch-home") }
    }

    // ── 第一页：待巩固 + 今天 + 连续 ─────────────────────────────────────────
    private var glance: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(d?.due ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("类待巩固")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 10) {
                Gauge(value: d?.progress() ?? 0) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(d?.done() ?? 0)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(WatchInk.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天 \(d?.done() ?? 0)/\(d?.goal ?? 12) 题")
                        .font(.footnote.weight(.semibold))
                    Label("连续 \(d?.streak ?? 0) 天", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(WatchInk.flame)
                }
            }
            Spacer(minLength: 0)
            if store.offline, let t = d?.updated {
                Text("离线 · 上次同步 \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            } else if let first = d?.next.first {
                Text("先复习：\(first.name)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)          // 圆角屏的下角会切掉贴底的东西
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("错题本")
    }

    // ── 第二页：先复习这几类 ────────────────────────────────────────────────
    private var nextPage: some View {
        List {
            let items = d?.next ?? []
            if items.isEmpty {
                Label("错题都订正完了", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(WatchInk.ok)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(item.lesson).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.wrongText).foregroundStyle(WatchInk.red)
                        if let ok = item.okText { Text(ok).foregroundStyle(WatchInk.ok) }
                    }
                    .font(.caption2)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.10)))
            }
            if let d, d.due > items.count {
                Text("还有 \(d.due - items.count) 类，在 iPhone 上复习")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("先复习")
    }
}

/// `-complications 1` 的验证页：四种表盘复杂功能各摆一个，深色底近似表盘。
struct ComplicationGallery: View {
    let digest: ReviewDigest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ReviewCircular(digest: digest).frame(width: 50, height: 50)
                    ReviewCorner(digest: digest).frame(width: 50, height: 50)
                }
                ReviewRectangular(digest: digest)
                    .padding(8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                ReviewInline(digest: digest).font(.footnote).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { if digest != nil { LaneSignal.ready("watch-complications") } }
        .onChange(of: digest) { _, d in if d != nil { LaneSignal.ready("watch-complications") } }
    }
}
