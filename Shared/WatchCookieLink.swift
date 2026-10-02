// WatchCookieLink.swift —— 总部共享（~/Dev/tools/dev/lib/tools/macapp/swift-shared/，产品仓 Shared/ 下放逐字节副本）
//
// iPhone → Apple Watch 的登录态转交：把服务端发的那一枚会话 cookie 递给手表，手表装进自己的 HTTPCookieStorage，
// 之后手表上的 URLSession 请求原样带上它，业务代码一行不改。产品只给两个参数：cookie 名、服务地址。
// 2026-10-02 照成长小金库 WatchLink / WatchSessionReceiver 抽成通用件，错题本首用；进 iPhone 主 App 与手表 App
// 两个 application target（multiplatform.py SHARED_SWIFT 的 phone_watch 范围）。主 App 同一 target 还编 macOS /
// visionOS：WatchConnectivity 只在 iOS / watchOS 有，其余平台这里全是空操作。
import Foundation
#if os(iOS) || os(watchOS)
import WatchConnectivity
#endif

/// iPhone 发、手表收的一对，同一个类型。
///
/// - iPhone：App 启动时 `activate()`；登录 / 恢复 / 注册成功后 `publishSession()`；退出 / 注销后 `publishSignedOut()`。
///   走 `updateApplicationContext`：只保留最新一份，手表下次启动时就能读到，iPhone 不用开着；每份带时间戳，
///   连着两次「登录了」也各算一次。没配对手表、手表上没装本 App 时什么都不发 —— 这是常态，不是故障。
/// - 手表：App 启动时 `activate()`（激活完成会先读一遍 iPhone 最近发的那份）；收到带 cookie 的就装上，
///   收到不带 cookie 的就删掉；之后看 `change` 决定重新拉数据还是回到「在 iPhone 上登录」。
/// - 服务地址比对（scheme + host + port）：两端不一致时整份忽略 —— iPhone 指着本地验证服务时，
///   手表若指着线上，就不能把一个服务的会话拿去敲另一个服务的门。
///
/// 转的是同一个会话，不是新造一份：服务端吊销（改密码、注销）对手表同样生效。
/// WCSession 全局只有一个 delegate：一个 App 里只建一个实例（产品自己放一个 static let）。
@MainActor
final class WatchCookieLink: NSObject, ObservableObject {
    /// 上下文里的键 —— 两端只认这几个。
    enum Key {
        static let name = "cookie_name"
        static let value = "cookie_value"
        static let expires = "expires"
        static let base = "base"
        static let at = "at"
    }

    /// 手表收到的一次登录态变化。带序号：连着两次「登录了」（换了一枚 cookie）也要各触发一次。
    struct Change: Equatable {
        let signedIn: Bool
        let serial: Int
    }

    let cookieName: String
    private let base: () -> URL

    /// 手表端：最近一次登录态变化（iPhone 端恒为 nil）。界面据此重新拉数据或清空。
    @Published private(set) var change: Change?
    private var serial = 0

    /// - Parameters:
    ///   - cookieName: 服务端会话 cookie 的名字（如 `edu_sess`）。
    ///   - base: 当前服务地址；每次用时现取（产品可能用启动参数把它指向本地验证服务）。
    init(cookieName: String, base: @escaping () -> URL) {
        self.cookieName = cookieName
        self.base = base
        super.init()
    }

    // ── 两端共用：读 / 装 cookie ────────────────────────────────────────────

    /// 当前服务地址下的会话 cookie（HttpOnly 也读得到：这是本 App 自己的 cookie 存储）。
    func sessionCookie() -> HTTPCookie? {
        HTTPCookieStorage.shared.cookies(for: base())?.first { $0.name == cookieName && !$0.value.isEmpty }
    }

    /// 装上一枚会话 cookie；`value` 为 nil 或空就只删不装。装在当前服务地址的 host 下、Path=/。
    func installCookie(_ value: String?, expires: Date?) {
        let url = base(), jar = HTTPCookieStorage.shared
        for c in jar.cookies(for: url) ?? [] where c.name == cookieName { jar.deleteCookie(c) }
        guard let value, !value.isEmpty, let host = url.host else { return }
        var props: [HTTPCookiePropertyKey: Any] = [.name: cookieName, .value: value, .domain: host, .path: "/"]
        if url.scheme == "https" { props[.secure] = "TRUE" }
        if let expires { props[.expires] = expires }
        if let c = HTTPCookie(properties: props) { jar.setCookie(c) }
    }

    /// scheme + host + port 一致才算同一个服务（路径、末尾斜杠不算）。
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? defaultPort(a)) == (b.port ?? defaultPort(b))
    }

    private static func defaultPort(_ u: URL) -> Int? {
        switch u.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// 手表端收到一份上下文后的处理（单独拿出来，便于不配对模拟器也能测）。返回是否采纳。
    @discardableResult
    func apply(_ ctx: [String: Any]) -> Bool {
        guard !ctx.isEmpty else { return false }                       // 从没收到过任何上下文
        if let name = ctx[Key.name] as? String, name != cookieName { return false }
        guard let s = ctx[Key.base] as? String, let from = URL(string: s), Self.sameOrigin(from, base()) else {
            return false
        }
        let value = ctx[Key.value] as? String
        let expires = (ctx[Key.expires] as? Double).map { Date(timeIntervalSince1970: $0) }
        installCookie(value, expires: expires)
        serial += 1
        change = Change(signedIn: value?.isEmpty == false, serial: serial)
        return true
    }

    #if os(iOS)
    // ── iPhone：发 ─────────────────────────────────────────────────────────

    /// 激活完成前想发的那一份（激活是异步的，开机就恢复登录时常会赶在它前面）。
    private var pending: [String: Any]?
    /// iPhone 这边当前是否登录着 —— 换表 / 装上手表 App 时只在登录着才补发
    private var signedIn = false

    func activate() {
        guard WCSession.isSupported() else { return }               // iPad 上不支持：直接什么都不做
        let s = WCSession.default
        s.delegate = self
        if s.activationState != .activated { s.activate() }
    }

    func publishSession() {
        signedIn = true
        guard let c = sessionCookie() else { return }
        var ctx: [String: Any] = [Key.name: cookieName, Key.value: c.value, Key.base: base().absoluteString,
                                  Key.at: Date().timeIntervalSince1970]
        if let e = c.expiresDate { ctx[Key.expires] = e.timeIntervalSince1970 }
        send(ctx)
    }

    func publishSignedOut() {
        signedIn = false
        send([Key.name: cookieName, Key.base: base().absoluteString, Key.at: Date().timeIntervalSince1970])
    }

    private func send(_ ctx: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else {
            pending = ctx
            activate()
            return
        }
        pending = nil
        guard s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(ctx)
    }
    #elseif os(watchOS)
    // ── 手表：收 ───────────────────────────────────────────────────────────

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publishSession() {}
    func publishSignedOut() {}
    #else
    // ── Mac / Vision Pro：没有手表这一头 ──────────────────────────────────────

    func activate() {}
    func publishSession() {}
    func publishSignedOut() {}
    #endif
}

#if os(iOS)
extension WatchCookieLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            if let p = self.pending { self.send(p) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 换了一块手表：旧会话失效，重新激活才能给新手表发
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 配对或装上手表 App 之后，补发一次当前的登录态
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            guard self.signedIn, session.isPaired, session.isWatchAppInstalled else { return }
            self.publishSession()
        }
    }
}
#elseif os(watchOS)
extension WatchCookieLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.apply(ctx) }
    }
}
#endif
