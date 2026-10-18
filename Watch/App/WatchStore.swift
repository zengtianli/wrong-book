import Foundation
import WidgetKit

/// 手表上的复习摘要：和 iPhone 同一个学习库、同一份存档、同一套解析（Api / Lessons / WrongBook），不另算。
///
/// 手表没有 WebKit，读不到 iPhone 练习页的本机存档，所以读服务端那一份（练习页自己同步上去的 `/api/archive`，
/// 也是 iPhone 错题本缺课时的兜底来源）。课名取 `/api/lessons` 清单，不下载课页。
/// 不开长连接：抬腕回到前台拉一次（一分钟内不重拉），复杂功能读刷新时写下的那份摘要。
@MainActor
final class WatchStore: ObservableObject {
    enum Phase: Equatable {
        case checking, signedOut, ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .checking
    @Published private(set) var digest: ReviewDigest?
    /// 连不上学习库、正在显示上次同步的那份
    @Published private(set) var offline = false
    private var lastLoad: Date?
    private var loading = false

    /// 开屏：有登录态就先摆出上次那份，再去拉新的。
    /// 验证通道：模拟器上的手表不配对 iPhone，照 iPhone 的做法认 `-api_base / -dev_user / -dev_pw`。
    func restore() async {
        let d = UserDefaults.standard
        if let u = d.string(forKey: "dev_user"), let pw = d.string(forKey: "dev_pw") {
            do { try await Api.login(user: u, password: pw) } catch {
                phase = .failed(Api.displayError(error))
                return
            }
        }
        guard WatchLink.shared.sessionCookie() != nil else {
            clear()
            return
        }
        if digest == nil, let cached = DigestSnapshot.load() {
            digest = cached
            phase = .ready
        }
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let manifest = Api.lessonManifest()
            async let archive = Api.archiveSnapshot()
            let pack = LessonPack(lessons: LessonPack.lessons(fromManifest: try await manifest, scope: ""),
                                  dailyGoal: 12, problem: nil)
            let snap = try await archive
            let fresh = ReviewDigest.make(book: WrongBook.parse(archive: snap, pack: pack),
                                          profile: GrowthProfile.parse(archive: snap))
            digest = fresh
            offline = false
            phase = .ready
            lastLoad = Date()
            DigestSnapshot.save(fresh)
            WidgetCenter.shared.reloadAllTimelines()
        } catch let f as Api.Failure where f.statusCode == 401 {
            // 会话被服务端吊销（改密码 / 注销）：和 iPhone 退出一样处理
            WatchLink.shared.installCookie(nil, expires: nil)
            clear()
        } catch {
            if digest != nil {
                offline = true
                phase = .ready
            } else {
                phase = .failed(String(localized: "暂时连不上学习库"))
            }
        }
    }

    /// 回到前台：没登录就再看一次有没有收到 iPhone 的登录态；登录着就刷新（一分钟内不重拉）。
    func refreshIfStale() async {
        switch phase {
        case .signedOut, .failed: await restore()
        case .checking: return
        case .ready:
            if let t = lastLoad, Date().timeIntervalSince(t) < 60 { return }
            await load()
        }
    }

    /// iPhone 退出 / 注销了，或服务端吊销了会话：清掉摘要和表盘那份。
    func clear() {
        digest = nil
        offline = false
        lastLoad = nil
        DigestSnapshot.save(nil)
        WidgetCenter.shared.reloadAllTimelines()
        phase = .signedOut
    }
}
