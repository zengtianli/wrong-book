import SwiftUI

/// Apple Watch 版：抬腕看的**只读**一面 —— 待巩固几类、今天做了几题、连续几天、先复习哪几类。
///
/// 和 iPhone 是同一个学习库、同一份存档、同一套解析（Api / Lessons / WrongBook），不另算任何数。
/// 不做题：练习引擎是网页（practice.js），手表没有 WebKit；做题回到 iPhone / iPad / Mac。
/// 登录态由 iPhone 递过来（WatchLink → 总部 WatchCookieLink）；模拟器验收照旧用 -api_base / -dev_user / -dev_pw。
@main
struct WrongBookWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            // 控件跟 iPhone 界面一样用错题本的绿（导航标题取的是全局强调色，见 project.yml 的 WatchAccent）
            WatchRootView().environmentObject(store).tint(WatchInk.accent)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if UserDefaults.standard.bool(forKey: "complications") {
                // 验证通道：`-complications 1` 把四种表盘复杂功能摆成一页（表盘上的截不到）
                ComplicationGallery(digest: store.digest)
            } else {
                switch store.phase {
                case .checking: ProgressView()
                case .signedOut: WatchSignedOutView()
                case .ready: WatchHomeView()
                case .failed(let why): WatchFailedView(message: why)
                }
            }
        }
        .task {
            WatchLink.shared.activate()
            await store.restore()
        }
        // iPhone 登录 / 换账号 / 退出：WatchCookieLink 已经装好或删掉了 cookie，这里只决定重拉还是清空
        .onReceive(WatchLink.shared.$change.compactMap { $0 }) { change in
            if change.signedIn {
                Task { await store.load() }
            } else {
                store.clear()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshIfStale() }
        }
    }
}

/// 没有登录态：只说一句话，指向 iPhone。手表上不放输入框。
struct WatchSignedOutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(WatchInk.accent)
            Text(String(localized: "在 iPhone 上登录\n\(String(localized: "app.name"))"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(String(localized: "登录后手表会自动同步"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }
}

struct WatchFailedView: View {
    @EnvironmentObject var store: WatchStore
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(WatchInk.red)
            Text(message).font(.footnote).multilineTextAlignment(.center)
            Button(String(localized: "重试")) { Task { await store.restore() } }
                .tint(WatchInk.accent)
        }
        .padding(.horizontal, 6)
    }
}
