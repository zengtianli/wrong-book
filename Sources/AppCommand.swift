#if os(macOS)
import AppKit
import Foundation

/// Mac 版 App 可执行文件的命令入口：`mistakes` 把 config / update / offline / app 原样转到这里
/// （`Contents/MacOS/WrongBook config status --json`）。沙盒容器里的偏好、登录态、离线副本和 iCloud Drive
/// 更新目录的授权都只在 App 自己手里，所以由这个可执行文件读写；命令进程不开窗口、不进 Dock、不弹任何框。
///
/// - config：总部共用命令层 `AppLifecycleCLI`，与「配置与更新」面板是同一个 `AppConfiguration`。
/// - update：面板在 Mac 上读更新用的是沙盒目录授权（`MacSandboxUpdateAccess`），共用层的 `update` 走不到它，
///   所以这里用面板同一条读取与校验，输出沿用共用层的字段名。沙盒里的 App 换不了自己：`install` 做到面板
///   「打开发行包」之前那一步（核对发行包身份、大小与 SHA256），然后以 `manual_install` 给出发行包位置。
/// - offline sync / reset、app logout：与窗口里的同步、停用副本、退出登录是同一份 `LessonSync` 与同一个 Cookie 库。
@MainActor
enum AppCommand {
    static let command = "mistakes"
    static let verbs = ["config", "update", "offline", "app"]
    /// 命令改了运行中的窗口也该跟着变的东西时发这条通知（沙盒里只能带一个字符串，不带字典）。
    static let followName = Notification.Name("cyou.tianli.wrongbook.command")
    /// 窗口这一侧要不要跟：验证车道与演示启动（-lane_* / -dev_user / -api_base）连的不是正式资料，不跟。
    static let windowFollows = !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-lane_") || $0 == "-dev_user" || $0 == "-api_base" }

    /// 不是命令返回 nil，照常进界面。App 自己的启动参数都以 `-` 开头，不会撞上这几个动词。
    static func run(_ arguments: [String]) -> Int32? {
        guard let verb = arguments.first, verbs.contains(verb) else { return nil }
        if verb == "config" { return AppLifecycleCLI.run(arguments, product: product) }
        let json = arguments.contains("--json")
        let name = arguments.prefix(2).filter { !$0.hasPrefix("-") }.joined(separator: " ")
        do {
            let parsed = try parse(Array(arguments.dropFirst()))
            guard parsed.positionals.count == 1 else { throw Failure.usage(syntax) }
            let out: (body: [String: Any], text: String)
            switch (verb, parsed.positionals[0]) {
            case ("update", "check"): out = try updateCheck()
            case ("update", "install"): out = try updateInstall(parsed)
            case ("offline", "sync"): out = try offlineSync()
            case ("offline", "reset"): out = try offlineReset(parsed)
            case ("app", "logout"): out = try logout(parsed)
            default: throw Failure.usage(syntax)
            }
            var body = out.body
            body["ok"] = true; body["command"] = name
            emit(body, text: out.text, json: json)
            return 0
        } catch let failure as Failure {
            let error: [String: Any] = ["code": failure.code, "message": failure.message]
            var body = failure.extra
            body["ok"] = false; body["command"] = name; body["error"] = error
            if json { emit(body, text: "", json: true) }
            else { FileHandle.standardError.write(Data((failure.message + "\n").utf8)) }
            return failure.exit
        } catch {
            let message = error.localizedDescription
            if json { emit(["ok": false, "command": name, "error": ["code": "failed", "message": message]], text: "", json: true) }
            else { FileHandle.standardError.write(Data((message + "\n").utf8)) }
            return 1
        }
    }

    static let syntax = "用法：\(command) config status | export -o <file> | import <file> --yes | sync on|off --yes；"
        + "\(command) update check | install --yes [--dry-run]；\(command) offline sync | reset --yes；\(command) app logout --yes（都可加 --json）"

    // MARK: config

    private static var product: AppLifecycleCLI.Product {
        var product = AppLifecycleCLI.Product(command: command, name: "错题本", configuration: MobileProductLifecycle.configuration,
                                              updateSource: .privateCloud(channel: MobileProductLifecycle.macChannel), windowEntry: "配置与更新")
        // 导入或同步改了提醒的开关与时间：没开着窗口时由命令进程自己把本机通知重排一遍，开着的窗口另由 follow 跟上。
        // 隔离运行与没有包身份的进程不碰系统通知。
        if Bundle.main.bundleIdentifier != nil, ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil {
            product.changed = { _ = try? wait(10) { _ = await Reminder.reschedule(ask: false) } }
        }
        return product
    }

    // MARK: update

    private static var current: (version: String, build: String, bundleID: String) {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
         Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0", Bundle.main.bundleIdentifier ?? "")
    }
    private static var running: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { $0.processIdentifier != own }
    }

    private struct Checked { let release: AppRelease; let state: String; let message: String; let body: [String: Any] }
    /// 面板「检查更新」那一次读取：同一个目录授权、同一份发行记录校验、同样的三种结论。
    private static func checked() throws -> Checked {
        let now = current, channel = MobileProductLifecycle.macChannel
        let base: [String: Any] = ["current": ["version": now.version, "build": now.build],
                                   "source": ["kind": "private_cloud", "channel": channel, "access": "sandbox_bookmark"], "app_running": running]
        let found = Box<Result<AppRelease, Error>>()
        MacSandboxUpdateAccess.check(bundleID: now.bundleID, channel: channel) { found.set($0) }
        spin(30) { found.value != nil }
        let release: AppRelease
        switch found.value {
        case .success(let value)?: release = value
        case .failure(let error)?: throw Failure(exit: 1, code: "check_incomplete", message: "检查未完成：" + error.localizedDescription, extra: base)
        case nil: throw Failure(exit: 1, code: "check_incomplete", message: "检查未完成：30 秒内没有读到发行记录", extra: base)
        }
        let state: String, message: String
        if release.isNewer(than: now.version, build: now.build) {
            state = "update_available"; message = "有新版 \(release.version) (\(release.build))，当前 \(now.version) (\(now.build))。升级会保留本机配置。"
        } else if AppVersion.compare(now.version, release.version) == .orderedDescending {
            state = "ahead_of_channel"; message = "当前 \(now.version) (\(now.build))；此渠道正式发行版本为 \(release.version) (\(release.build))。"
        } else { state = "up_to_date"; message = "当前已是此渠道最新版：\(now.version) (\(now.build))。" }
        let latest: [String: Any] = ["version": release.version, "build": release.build, "channel": release.channel ?? NSNull(),
                                     "package": release.downloadURL?.path ?? NSNull(), "sha256": release.sha256 ?? NSNull(),
                                     "size_bytes": release.size ?? NSNull(), "installation": release.installation ?? NSNull()]
        return Checked(release: release, state: state, message: message,
                       body: base.merging(["latest": latest, "update_available": state == "update_available", "state": state, "message": message]) { $1 })
    }

    private static let manual = "沙盒里的 App 换不了自己：发行包是需要手动安装的 ZIP，解开后把「错题本」放进「应用程序」替换旧版，配置与登录保留。"
    private static func updateCheck() throws -> ([String: Any], String) {
        let check = try checked(), newer = check.state == "update_available"
        let how = newer ? "运行 \(command) update install --yes 核对发行包（身份、大小、SHA256）并给出位置；或在 App 的「配置与更新」里点「打开发行包」。\(manual)" : "不需要升级。"
        var body = check.body
        let button: Any = newer ? "打开发行包" : NSNull(), install: Any = newer ? "\(command) update install --yes" : NSNull()
        body["upgrade"] = ["in_app": false, "button": button, "how": how, "download_url": NSNull(), "command": install] as [String: Any]
        return (body, check.message + (newer ? "\n" + how : ""))
    }

    private static func updateInstall(_ p: Arguments) throws -> ([String: Any], String) {
        let check = try checked()
        var body = check.body
        guard check.state == "update_available" else {
            body["installed"] = false
            return (body, check.message + "不需要升级。")
        }
        let now = current, release = check.release
        if p.flags.contains("--dry-run") {
            body["dry_run"] = true; body["installed"] = false; body["installation"] = release.installation ?? NSNull()
            body["would_install"] = ["from": ["version": now.version, "build": now.build], "to": ["version": release.version, "build": release.build]]
            body["will_quit_app"] = false; body["will_relaunch"] = false
            return (body, "有新版 \(release.version) (\(release.build))（未执行）。\(manual)")
        }
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required", message: "会核对 iCloud Drive 里的发行包（身份、大小、SHA256）并给出它的位置；不替换 App：确认请加 --yes（或先 --dry-run）")
        }
        // 面板「打开发行包」的校验原样跑一遍；最后那一步「交给系统打开」换成只报告位置，命令不弹任何窗口。
        let verified = Box<Result<Void, Error>>()
        MacSandboxUpdateAccess.openPackage(release, bundleID: now.bundleID, channel: MobileProductLifecycle.macChannel,
                                           open: { _, finished in finished(true) }) { verified.set($0) }
        spin(300) { verified.value != nil }
        body["installed"] = false
        switch verified.value {
        case .failure(let error)?: throw Failure(exit: 1, code: "upgrade_failed", message: "发行包未通过核对，当前 App 未动：" + error.localizedDescription, extra: body)
        case nil: throw Failure(exit: 1, code: "upgrade_failed", message: "发行包没有在 300 秒内读完，当前 App 未动（可能还没从 iCloud 下载完）", extra: body)
        case .success?: break
        }
        body["package"] = release.downloadURL?.path ?? NSNull(); body["package_verified"] = true
        throw Failure(exit: 1, code: "manual_install",
                      message: "有新版 \(release.version) (\(release.build))，发行包已核对：\(release.downloadURL?.path ?? "")。\(manual)", extra: body)
    }

    // MARK: offline · app

    /// 验证通道，同 App 的启动参数 `-dev_user <u> -dev_pw <pw>`（配 `-api_base` 指向本地演示库）：
    /// 只有显式传了才生效，生产路径上这两个键永远是 nil。
    private static func devLogin() throws {
        let defaults = UserDefaults.standard
        guard let user = defaults.string(forKey: "dev_user"), let password = defaults.string(forKey: "dev_pw") else { return }
        try wait(25) { try await Api.login(user: user, password: password) }
    }

    /// 当前登录的是谁：用的是 App 自己 Cookie 库里那份登录态，命令不收账号密码。
    private static func signedIn() throws -> Status {
        do { return try wait(25) { try await Api.status(timeout: 20) } }
        catch let failure as Failure { throw failure }
        catch let error as Api.Failure where error.statusCode == 401 {
            throw Failure(exit: 1, code: "not_signed_in", message: "这台 Mac 上的错题本没有登录：先在 App 里登录（登录要真人输密码或验证码）")
        } catch { throw Failure(exit: 1, code: "unreachable", message: "连不上 \(Api.base.absoluteString)：" + error.localizedDescription) }
    }

    private static func copies() -> [String: Any] {
        guard let directory = LessonPaths.downloads,
              let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["active": false, "directory": NSNull(), "lessons": [] as [Any], "count": 0]
        }
        let lessons: [[String: Any]] = ((manifest["lessons"] as? [[String: Any]]) ?? []).map { lesson in
            let file = lesson["file"] as? String ?? ""
            let bytes: Int? = (try? directory.appendingPathComponent(file).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            return ["file": file, "sha256": lesson["sha256"] ?? NSNull(), "on_disk": bytes != nil, "bytes": bytes.map { $0 as Any } ?? NSNull()]
        }
        return ["active": true, "directory": directory.path, "lessons": lessons, "count": lessons.count]
    }

    /// 顶栏「同步」/ ⌘R 与设置里「现在检查更新」是同一个动作：强制重拉这台 Mac 上的副本。
    private static func offlineSync() throws -> ([String: Any], String) {
        try devLogin()
        let status = try signedIn()
        let sync = LessonSync.shared
        sync.setUser(status.user)
        try wait(600) { await sync.sync(force: true) }
        UserDefaults.standard.synchronize()
        let copy = copies(), note = sync.note
        var body: [String: Any] = ["user": status.user, "synced": copy["active"] as? Bool == true, "note": note ?? NSNull(), "app_running": running]
        body.merge(copy) { $1 }
        guard copy["active"] as? Bool == true else {
            throw Failure(exit: 1, code: "sync_failed", message: note ?? "个人课程没有同步下来", extra: body)
        }
        follow("offline-synced")
        let missing = (copy["lessons"] as? [[String: Any]] ?? []).filter { $0["on_disk"] as? Bool != true }.count
        return (body, "已同步 \(copy["count"] ?? 0) 份个人课程" + (missing > 0 ? "（\(missing) 份不在盘上）" : "") + "：\(copy["directory"] ?? "")")
    }

    private static func offlineReset(_ p: Arguments) throws -> ([String: Any], String) {
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required", message: "会停用这台 Mac 上的课程副本（个人文件照留，重新同步即恢复）：确认请加 --yes")
        }
        let had = UserDefaults.standard.dictionary(forKey: "privateLibraryLastAuthenticatedV2") != nil
        LessonSync.shared.reset()
        UserDefaults.standard.synchronize()
        follow("offline-reset")
        return (["reset": true, "had_active_copy": had, "files_kept": true, "app_running": running, "check_with": "\(command) offline sync"],
                had ? "已停用本机课程副本，个人文件照留；\(command) offline sync 重新同步。" : "本机没有生效的课程副本，未改动。")
    }

    private static func logout(_ p: Arguments) throws -> ([String: Any], String) {
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required", message: "会退出这台 Mac 上错题本的登录并停用课程副本（账号与云端资料不动，再次使用要真人登录）：确认请加 --yes")
        }
        try devLogin()
        let cookies = { (HTTPCookieStorage.shared.cookies(for: Api.base) ?? []).filter { $0.name == "edu_sess" } }
        let had = !cookies().isEmpty
        // 与窗口里「退出登录」同一顺序：先停本机副本，再让服务端作废会话，最后清本机 Cookie。
        LessonSync.shared.setUser(nil)
        try wait(25) { await Api.logout() }
        cookies().forEach(HTTPCookieStorage.shared.deleteCookie)
        UserDefaults.standard.synchronize()
        let flushed = Box<Bool>()
        URLSession.shared.flush { flushed.set(true) }
        spin(5) { flushed.value != nil }
        follow("logout")
        return (["logged_out": true, "had_session": had, "session_cookie_left": !cookies().isEmpty, "app_running": running],
                had ? "已退出这台 Mac 上错题本的登录，课程副本已停用。" : "这台 Mac 上的错题本本来就没有登录，未改动。")
    }

    /// 窗口开着时让它跟上：它自己把内存里的那一半做完（见 RootView 的 `.onReceive`）。隔离运行不发。
    private static func follow(_ what: String) {
        guard ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil else { return }
        DistributedNotificationCenter.default().postNotificationName(followName, object: what, userInfo: nil, deliverImmediately: true)
    }

    // MARK: Plumbing

    struct Failure: Error {
        let exit: Int32, code: String, message: String
        var extra: [String: Any] = [:]
        static func usage(_ message: String) -> Failure { Failure(exit: 2, code: "usage", message: message) }
    }
    private struct Arguments { var positionals: [String] = []; var flags: Set<String> = [] }
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
    }

    private static func parse(_ arguments: [String]) throws -> Arguments {
        var parsed = Arguments(), index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if ["--json", "--yes", "--dry-run"].contains(argument) { parsed.flags.insert(argument) }
            // 验证通道：`-api_base <url>` 这类单横线成对参数由 UserDefaults 自己读（同 App 启动参数），这里跳过。
            else if argument.hasPrefix("-"), !argument.hasPrefix("--"), index + 1 < arguments.count { index += 1 }
            else if argument.hasPrefix("-") { throw Failure.usage("未知参数 \(argument)。" + syntax) }
            else { parsed.positionals.append(argument) }
            index += 1
        }
        return parsed
    }

    private static func emit(_ body: [String: Any], text: String, json: Bool) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])) ?? Data("{\"ok\":false}".utf8)
        FileHandle.standardOutput.write(json ? data + Data("\n".utf8) : Data((text + "\n").utf8))
    }

    /// 主线程转着 run loop 等：主 actor 上的任务和各回调都投回主队列。
    private static func spin(_ seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }
    @discardableResult
    private static func wait<T>(_ seconds: TimeInterval, _ work: @escaping @MainActor () async throws -> T) throws -> T {
        let box = Box<Result<T, Error>>()
        let task = Task { @MainActor in
            do { box.set(.success(try await work())) } catch { box.set(.failure(error)) }
        }
        spin(seconds) { box.value != nil }
        guard let result = box.value else {
            task.cancel()
            throw Failure(exit: 1, code: "timeout", message: "\(Int(seconds)) 秒内没有完成")
        }
        return try result.get()
    }
}
#endif
