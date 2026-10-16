#if DEBUG && os(iOS)
import Foundation

/// Actual native Session/Api phone paths. The isolated coordinator supplies
/// fixture codes; this phase never certifies carrier delivery or calls PNVS.
@MainActor
enum AccountPhoneSelfTest {
    static func run(_ plan: [String: String], session: Session) async throws -> [String: Bool] {
        guard let a = plan["phone_a"], let b = plan["phone_b"], let c = plan["phone_c"],
              let user = plan["user"], let password = plan["new"], let recovered = plan["phone_recovered"],
              let token = plan["phone_token"], let base = URL(string: plan["phone_coordinator"] ?? ""),
              base.host == "127.0.0.1", base.scheme == "http" else { throw AccountSelfTest.Stop() }
        var checks: [String: Bool] = [:]
        var sentAt: [String: Date] = [:]
        func require(_ name: String, _ condition: Bool) throws {
            checks[name] = condition
            if !condition { throw AccountSelfTest.Stop() }
        }
        func grant(_ phone: String, _ purpose: String, authenticated: Bool = true, wrong: Bool = false) async throws -> String {
            // Keep the production resend policy. No database edits or timing
            // overrides are needed to exercise repeated use of one number.
            if let previous = sentAt[phone] {
                let remaining = 61 - Date().timeIntervalSince(previous)
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            }
            let result = try await Api.accountRequest("api/phone_send", body: ["phone": phone, "purpose": purpose,
                "password": authenticated ? password : "", "request_id": UUID().uuidString])
            sentAt[phone] = Date()
            guard let challenge = result["challenge"] as? String else { throw AccountSelfTest.Stop() }
            var request = URLRequest(url: base.appendingPathComponent("receive"))
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue(token, forHTTPHeaderField: "X-WrongBook-QA")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["phone": phone, "challenge": challenge])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let reply = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let code = reply["code"] else { throw AccountSelfTest.Stop() }
            if wrong {
                var refused = false
                do { _ = try await Api.accountRequest("api/phone_verify", body: ["challenge": challenge, "code": "invalid"]) }
                catch let error as Api.Failure { refused = error.statusCode == 400 }
                try require("phone_verification.wrong_code_refused", refused)
            }
            let verified = try await Api.accountRequest("api/phone_verify", body: ["challenge": challenge, "code": code])
            guard let value = verified["grant"] as? String, !value.isEmpty else { throw AccountSelfTest.Stop() }
            return value
        }
        await session.login(user: user, password: password)
        try require("phone_binding.original_user", session.status?.user == user)
        let before = try await Api.archiveSnapshot()
        let first = try await grant(a, "phone_new", wrong: true)
        _ = try await session.updateAccount("api/phone_bind", body: ["phone": a, "password": password, "grant": first])
        let bound = try await Api.accountRequest("api/me")
        try require("phone_binding.verified_identity", bound["phone"] as? String == "+86" + a && bound["phone_verified"] as? Bool == true && session.status?.user == user)
        try require("phone_verification.native_grant", !first.isEmpty)
        let next = try await grant(b, "phone_change_new")
        var missingOldRefused = false
        do { _ = try await session.updateAccount("api/phone_bind", body: ["phone": b, "password": password, "grant": next]) }
        catch let error as Api.Failure { missingOldRefused = error.statusCode == 400 }
        try require("phone_change.old_ownership_required", missingOldRefused)
        let previous = try await grant(a, "phone_old")
        _ = try await session.updateAccount("api/phone_bind", body: ["phone": b, "password": password, "grant": next, "old_grant": previous])
        let changed = try await Api.accountRequest("api/me")
        let after = try await Api.archiveSnapshot()
        try require("phone_change.identity_and_archive", changed["phone"] as? String == "+86" + b && session.status?.user == user && before == after)
        await session.logout()
        let login = try await grant(b, "login", authenticated: false)
        await session.phoneAuthenticate(grant: login)
        try require("phone_login.native_session", session.status?.user == user && session.phase == .loggedIn)
        var replayRefused = false
        do { _ = try await Api.accountRequest("api/phone_login", body: ["grant": login]) }
        catch let error as Api.Failure { replayRefused = error.statusCode == 400 }
        try require("phone_login.consumed_grant_refused", replayRefused)
        await session.logout()
        let recovery = try await grant(b, "phone_recover", authenticated: false)
        _ = try await Api.accountRequest("api/phone_recover", body: ["grant": recovery, "new": recovered, "password": password])
        await session.login(user: b, password: password)
        try require("phone_recovery.old_password_revoked", session.phase == .loggedOut && session.error != nil)
        await session.login(user: b, password: recovered)
        let restored = try await Api.archiveSnapshot()
        try require("phone_recovery.identity_and_archive", session.status?.user == user && restored == before)
        _ = try await session.updateAccount("api/passwd", body: ["old": recovered, "new": password])
        await session.logout()
        let registration = try await grant(c, "register", authenticated: false)
        await session.phoneAuthenticate(grant: registration, registering: true, agreed: true)
        try require("phone_registration.native_session", session.phase == .loggedIn && session.status?.user != user)
        let empty = try await Api.archiveSnapshot()
        try require("phone_registration.empty_archive", empty.isEmpty)
        let identity = try await grant(c, "phone_identity", authenticated: false)
        _ = try await session.updateAccount("api/password_set", body: ["identity_grant": identity, "new": password])
        let deleted = await session.deleteAccount(password: password)
        try require("phone_registration.disposable_removed", deleted && session.phase == .loggedOut)
        return checks
    }
}
#endif
