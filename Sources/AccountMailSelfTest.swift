#if DEBUG && os(iOS)
import Foundation

/// A real-mail phase in the actual product process. Codes come only from the
/// coordinator's read-only IMAP receiver, never the service database or a mock.
@MainActor
enum AccountMailSelfTest {
    static func run(_ plan: [String: String], session: Session) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        func require(_ name: String, _ condition: Bool) throws {
            checks[name] = condition
            if !condition { throw AccountSelfTest.Stop() }
        }
        guard let a = plan["mail_a"], let b = plan["mail_b"], let c = plan["mail_c"], let d = plan["mail_d"],
              let user = plan["user"], let password = plan["new"],
              let recovered = plan["recovered"], let token = plan["coordinator_token"],
              let base = URL(string: plan["coordinator"] ?? ""), base.host == "127.0.0.1" else { throw AccountSelfTest.Stop() }
        func receive(_ email: String) async throws -> String {
            var request = URLRequest(url: base.appendingPathComponent("receive"))
            request.httpMethod = "POST"; request.timeoutInterval = 100
            request.setValue(token, forHTTPHeaderField: "X-WrongBook-QA")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = reply["code"] as? String, code.count == 6 else { throw AccountSelfTest.Stop() }
            return code
        }
        func send(_ email: String, _ purpose: String, authenticated: Bool = true) async throws -> String {
            let sent = try await Api.accountRequest("api/email_send", body: ["email": email, "purpose": purpose,
                "password": authenticated ? password : "", "request_id": UUID().uuidString])
            guard let challenge = sent["challenge"] as? String, !challenge.isEmpty else { throw AccountSelfTest.Stop() }
            return challenge
        }
        func grant(_ email: String, _ purpose: String, authenticated: Bool = true, testWrongCode: Bool = false) async throws -> String {
            let challenge = try await send(email, purpose, authenticated: authenticated)
            let code = try await receive(email)
            if testWrongCode {
                var rejected = false
                do { _ = try await Api.accountRequest("api/email_verify", body: ["challenge": challenge, "code": "invalid"]) }
                catch let error as Api.Failure { rejected = error.statusCode == 400 }
                try require("email_verification.wrong_code_refused", rejected)
            }
            let verified = try await Api.accountRequest("api/email_verify", body: ["challenge": challenge, "code": code])
            guard let value = verified["grant"] as? String, !value.isEmpty else { throw AccountSelfTest.Stop() }
            return value
        }
        await session.login(user: user, password: password)
        try require("email_binding.original_user", session.status?.user == user)
        let before = try await Api.archiveSnapshot()
        let first = try await grant(a, "email_new", testWrongCode: true)
        _ = try await session.updateAccount("api/email_bind", body: ["email": a, "password": password, "grant": first, "old_grant": ""])
        let bound = try await Api.accountRequest("api/me")
        try require("email_binding.verified_address", bound["email_verified"] as? Bool == true && bound["email"] as? String == a && session.status?.user == user)
        try require("email_verification.real_received_code", !first.isEmpty)
        let second = try await grant(b, "email_new")
        let previous = try await grant(a, "email_old")
        _ = try await session.updateAccount("api/email_bind", body: ["email": b, "password": password, "grant": second, "old_grant": previous])
        let changed = try await Api.accountRequest("api/me")
        let after = try await Api.archiveSnapshot()
        try require("email_change.identity_and_archive", changed["email"] as? String == b && session.status?.user == user && before == after)
        await session.logout()
        let recovery = try await grant(b, "recover", authenticated: false)
        _ = try await Api.accountRequest("api/recover", body: ["grant": recovery, "new": recovered])
        await session.login(user: b, password: password)
        try require("password_recovery.old_password_revoked", session.phase == .loggedOut && session.error != nil)
        await session.login(user: b, password: recovered)
        try require("password_recovery.native_login", session.status?.user == user)
        let restored = try await Api.archiveSnapshot()
        try require("password_recovery.data_preserved", restored == before)
        _ = try await session.updateAccount("api/passwd", body: ["old": recovered, "new": password])
        await session.logout()
        let blocked = try await send(c, "register", authenticated: false)
        _ = try await receive(c)
        var cooldown = false
        do { _ = try await send(c, "register", authenticated: false) }
        catch let error as Api.Failure { cooldown = error.statusCode == 429 }
        try require("abuse_protection.resend_cooldown", cooldown)
        var refusals = 0, exhausted = false
        for _ in 0..<6 {
            do { _ = try await Api.accountRequest("api/email_verify", body: ["challenge": blocked, "code": "invalid"]) }
            catch let error as Api.Failure {
                if error.statusCode == 400 { refusals += 1 }
                if error.statusCode == 429 { exhausted = true }
            }
        }
        try require("abuse_protection.wrong_code_budget", refusals > 0 && exhausted)
        let registration = try await grant(d, "register", authenticated: false)
        await session.register(email: d, password: password, nick: "隔离邮件验收", grant: registration)
        try require("registration.real_mail_native_session", session.phase == .loggedIn && session.status?.user != user && session.status != nil)
        let empty = try await Api.archiveSnapshot()
        try require("registration.empty_personal_archive", empty.isEmpty)
        let deleted = await session.deleteAccount(password: password)
        try require("registration.disposable_account_removed", deleted && session.phase == .loggedOut)
        try require("email_delivery.native_verification", checks["email_verification.real_received_code"] == true && checks["registration.real_mail_native_session"] == true)
        return checks
    }
}
#endif
