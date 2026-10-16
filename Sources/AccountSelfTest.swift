#if DEBUG && os(iOS)
import SwiftUI
import UIKit

/// Runs inside the actual iOS product, in an isolated simulator installation.
/// It never obtains credentials/codes from the process arguments or writes them
/// to its report. The coordinator supplies a private plan in the App container.
struct AccountSelfTestApp: App {
    var body: some Scene {
        WindowGroup { Color.clear.task { await AccountSelfTest.run() } }
    }
}

@MainActor
enum AccountSelfTest {
    nonisolated static var requested: Bool { CommandLine.arguments.contains("--account-self-test") }
    struct Stop: Error {}
    static func run() async {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["WRONGBOOK_ACCOUNT_PLAN"], let output = env["WRONGBOOK_ACCOUNT_OUTPUT"],
              let binding = env["WRONGBOOK_ACCOUNT_BINDING"],
              let url = URL(string: UserDefaults.standard.string(forKey: "api_base") ?? ""),
              url.host == "127.0.0.1", url.scheme == "http",
              let plan = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: input))) as? [String: String],
              let user = plan["user"], let old = plan["old"], let new = plan["new"],
              let phase = plan["phase"] else { exit(2) }
        let session = Session()
        var checks: [String: Bool] = [:]
        var failure: String?
        func require(_ name: String, _ condition: Bool) throws {
            checks[name] = condition
            if !condition { throw Stop() }
        }
        do {
            // Render the real login view in a hidden window outside the screen.
            let view = UIHostingController(rootView: LoginView().environmentObject(session))
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { throw Stop() }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: -30000, y: -30000, width: 390, height: 844)
            window.isHidden = true; window.rootViewController = view
            view.loadViewIfNeeded(); view.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            view.beginAppearanceTransition(true, animated: false); view.endAppearanceTransition()
            try await Task.sleep(for: .milliseconds(400))
            view.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: view.view.bounds.size).image { _ in
                view.view.drawHierarchy(in: view.view.bounds, afterScreenUpdates: true)
            }
            try image.pngData()!.write(to: URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("login-\(phase).png"))
            try require("native.login_view_offscreen", window.isHidden && !window.isKeyWindow && window.frame.maxX < 0 && view.view.window === window && view.presentedViewController == nil)
            window.rootViewController = nil
            switch phase {
            case "live-mail":
                checks.merge(try await AccountMailSelfTest.run(plan, session: session)) { _, new in new }
            case "exercise":
                await session.login(user: user, password: "deliberately-wrong-" + old)
                try require("login.wrong_password_refused", session.phase == .loggedOut && session.status == nil && session.error != nil)
                await session.login(user: user, password: old)
                try require("login.native_session", session.phase == .loggedIn && session.status?.user == user)
                let before = try await Api.archiveSnapshot()
                try require("data_preservation.fixture_present", before["edu:wrongbook-account-qa"] == plan["archive"])
                var refused = false
                do { _ = try await session.updateAccount("api/passwd", body: ["old": "wrong-" + old, "new": new]) }
                catch let error as Api.Failure { refused = error.statusCode == 403 }
                try require("password_change.wrong_old_refused", refused && session.status?.user == user)
                _ = try await session.updateAccount("api/passwd", body: ["old": old, "new": new])
                try require("password_change.identity_preserved", session.phase == .loggedIn && session.status?.user == user)
                let after = try await Api.archiveSnapshot()
                try require("data_preservation.after_password_change", before == after)
                await session.logout()
                try require("logout.native_cleared", session.phase == .loggedOut && session.status == nil)
                await session.login(user: user, password: old)
                try require("password_change.old_password_revoked", session.phase == .loggedOut && session.error != nil)
                await session.login(user: user, password: new)
                try require("password_change.new_password_login", session.phase == .loggedIn && session.status?.user == user)
            case "restore":
                await session.restore()
                try require("login.fresh_process_cookie_restore", session.phase == .loggedIn && session.status?.user == user)
                let archive = try await Api.archiveSnapshot()
                try require("data_preservation.fresh_process", archive["edu:wrongbook-account-qa"] == plan["archive"])
                await session.logout()
                try require("logout.native_cleared", session.phase == .loggedOut && session.status == nil)
            case "logged-out":
                await session.restore()
                try require("logout.fresh_process_denied", session.phase == .loggedOut && session.status == nil)
            case "delete":
                await session.login(user: user, password: new)
                try require("account_deletion.login", session.status?.user == user)
                let refused = await session.deleteAccount(password: "wrong-" + new)
                try require("account_deletion.wrong_password_refused", !refused && session.status?.user == user)
                let deleted = await session.deleteAccount(password: new)
                try require("account_deletion.completed", deleted && session.phase == .loggedOut && session.status == nil && session.deletionReceipt == nil)
                await session.login(user: user, password: new)
                try require("account_deletion.cannot_login", session.phase == .loggedOut && session.error != nil)
            default: throw Stop()
            }
        } catch { failure = String(describing: type(of: error)) }
        // No response bodies, usernames, addresses, tokens, grants or passwords.
        let raw: [String: Any] = ["schema_version": 1, "app_id": "wrong-book-ios", "phase": phase,
            "pid": ProcessInfo.processInfo.processIdentifier, "account_input_sha256": binding,
            "checks": checks, "failure_class": failure as Any? ?? NSNull(),
            "scope": phase == "live-mail"
                ? "Actual iOS App process; offscreen LoginView; production Session/Api; real SMTP and read-only IMAP receiver; isolated account data; SMS not exercised."
                : "Actual iOS App process; offscreen LoginView; production Session/Api account actions; isolated loopback service; no email/SMS exercised in this phase."]
        do {
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } catch { exit(3) }
        exit(failure == nil && !checks.isEmpty && checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}
#endif
