import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 进程入口。Mac 版的可执行文件同时是 `mistakes` 转调的命令入口（config / update / offline / app，见 AppCommand）：
/// 认出命令就在这里做完退出，不建任何窗口；其余照常进界面。
@main
enum WrongBookMain {
    @MainActor static func main() {
        #if DEBUG && os(iOS)
        if AccountSelfTest.requested {
            AccountSelfTestApp.main()
            return
        }
        #endif
        #if DEBUG && (os(macOS) || os(iOS))
        if ProductBasicsSelfTest.requested {
            #if os(macOS)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            Task { await ProductBasicsSelfTest.run() }
            RunLoop.main.run()
            #elseif os(iOS)
            ProductBasicsApp.main()
            #endif
            return
        }
        #endif
        #if os(macOS)
        if let code = AppCommand.run(Array(CommandLine.arguments.dropFirst())) { exit(code) }
        #endif
        WrongBookApp.main()
    }
}

struct WrongBookApp: App {
    #if os(macOS)
    // 平台验收车道的 Mac 静默启动（-lane_quiet）；不传那个参数时什么都不做
    @NSApplicationDelegateAdaptor(LaneAppDelegate.self) private var laneDelegate
    #endif
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session).lightAppearance().tint(Ink.accent)
                #if os(iOS)
                // Keep the system TabView clear; configuration lives in account settings and login.
                .appLifecycleMobile(productID: "wrong-book", channel: MobileProductLifecycle.channel, configuration: MobileProductLifecycle.configuration, placement: .settings)
                #else
                .appLifecycleMobile(productID: "wrong-book", channel: MobileProductLifecycle.channel, configuration: MobileProductLifecycle.configuration, placement: .settings)
                .safeAreaInset(edge: .bottom, spacing: 0) { ProductSettingsEntry().font(.footnote).padding(.vertical, 7) }
                #endif
                #if os(macOS)
                // 侧栏 + 错题列表 + 题目三栏并排，再窄就挤了
                .frame(minWidth: 900, minHeight: 620)
                #endif
        }
        #if os(macOS) || os(visionOS)
        .defaultSize(width: 1240, height: 820)
        #endif
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { ProductSettings.show() }.keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var session: Session
    @ObservedObject private var subscriptions = AISubscription.shared
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    /// 只认 iPad 的 regular：iPhone Pro Max 横屏时尺寸类也是 regular，但那块屏摆不下侧栏 + 列表 + 题目，
    /// 仍走原来的标签页。
    private var wide: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private let wide = true      // Mac 与 Vision Pro 的窗口一律按宽屏排
    #endif

    var body: some View {
        Group {
            if let r = UserDefaults.standard.string(forKey: "review"),
               r.contains(":") {
                // 验证通道：`-review <slug>:<gid>` 直接进某一类的复习。
                // 没有它，「复习出的是同类新题、不是原题」这条只能靠手点 ——
                // 而手点验不了的东西，等于没有验过。
                let parts = r.split(separator: ":", maxSplits: 1).map(String.init)
                LessonPreview(slug: parts[0], drillGid: parts[1])
            } else if UserDefaults.standard.bool(forKey: "papertest") {
                PaperSelfTest()
            } else if UserDefaults.standard.bool(forKey: "paperscan") {
                // 验证通道：`-paperscan 1` 直接开录卷子那一屏。
                // 它平时藏在「我的」二级页里，没有这条通道就只能靠人点进去看 ——
                // 而人点得到的东西，机器截不到就等于没验过。
                NavigationStack { PaperScanView().environmentObject(LessonSync.shared) }
            } else if let slug = UserDefaults.standard.string(forKey: "lesson") {
                // 验证通道：`-lesson <slug>` 直接开某一课，不必先登录。
                // 练习引擎本身不依赖登录（页面自包含，登录只决定分记不记得上），
                // 有了它「离线能不能做题」这条才验得了：不登录、不联网，照样该能做完一套。
                LessonPreview(slug: slug)
            } else {
                switch session.phase {
                case .checking:  SplashView()
                case .loggedOut: LoginView()
                case .loggedIn:
                    if wide { RegularHomeView() } else { HomeView() }
                }
            }
        }
        .environment(\.wideLayout, wide)
        .animation(.easeInOut(duration: 0.3), value: session.phase)
        .task {
            #if os(macOS)
            ProductSettings.installShortcuts()
            #endif
            // 平台验收车道：iPad 横屏、Mac 截图窗口尺寸（不传 -lane_* 时什么都不做）
            LaneSignal.applyOrientation()
            LaneSignal.applyWindowFrame()
            WatchLink.shared.activate()
        }
        .task { await session.restore(); await session.refreshDeletion() }
        #if os(macOS)
        // 窗口开着时跟上 `mistakes` 命令做的事（AppCommand）：导入或同步改了配置、停用副本、退出登录、重新同步。
        // 验证车道与演示启动不跟（它们不碰正式配置）。
        .task { if AppCommand.windowFollows { AppLifecycleCLI.follow(MobileProductLifecycle.configuration) } }
        .onReceive(DistributedNotificationCenter.default().publisher(for: AppCommand.followName)) { note in
            guard AppCommand.windowFollows else { return }
            switch note.object as? String {
            case "logout": Task { await session.logout() }
            case "offline-reset": LessonSync.shared.reset()
            case "offline-synced": Task { await LessonSync.shared.sync(force: true) }
            default: break
            }
        }
        #endif
        .task { await AISubscription.shared.listen() }
        .task { await subscriptions.listenForPurchaseIntents() }
        .task { await subscriptions.listenForStorefrontChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await session.refreshDeletion()
                    if session.phase == .loggedIn { await AISubscription.shared.refresh() }
                }
            }
        }
        .onChange(of: session.status?.user) { _, _ in AISubscription.shared.clearAccess() }
        // Apple Watch 跟着 iPhone 的登录态走（WatchLink）：服务端确认了是谁（登录 / 恢复 / 注册）就递 cookie，
        // 回到登录页（退出 / 注销）就递「已退出」。没网时离线打开（status 为空、仍算登录着）不算退出。
        .onChange(of: session.status?.user) { _, user in
            if user != nil { WatchLink.shared.publishSession() }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .loggedOut { WatchLink.shared.publishSignedOut() }
        }
        .onChange(of: session.credentialRevision) { _, _ in
            if session.status != nil { WatchLink.shared.publishSession() }
        }
        .alert("继续订阅", isPresented: Binding(
            get: { subscriptions.purchaseIntent != nil && session.phase == .loggedIn },
            set: { if !$0 { subscriptions.purchaseIntent = nil } }), presenting: subscriptions.purchaseIntent) { product in
            Button("继续") {
                subscriptions.purchaseIntent = nil
                Task { await subscriptions.purchase(product) }
            }
            Button("取消", role: .cancel) { subscriptions.purchaseIntent = nil }
        } message: { product in
            Text("订阅将绑定当前错题本账号 \(session.status?.nick ?? "")。\(product.displayName)，价格 \(product.displayPrice)。请在 Apple 购买确认页核对周期和金额。")
        }
        .alert("注销处理结果", isPresented: Binding(get: { session.deletionNotice != nil }, set: { if !$0 { session.deletionNotice = nil } })) {
            Button("好", role: .cancel) { session.deletionNotice = nil }
        } message: { Text(session.deletionNotice ?? "") }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            ProgressView().tint(Ink.red).scaleEffect(1.3)
        }
    }
}
