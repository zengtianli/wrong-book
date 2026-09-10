import Foundation
import WebKit

// Compile the production Session, Api and request binding. Only local library/archive
// storage is isolated; delayed responses run through the real URLSession.shared client.
enum LessonPaths {
    static var offlineReadOnly = false
    static var activeScope: String?
    @MainActor static func webDataStore(scope: String) -> WKWebsiteDataStore { .nonPersistent() }
    static func removeFiles(scope: String) throws {}
}

@MainActor final class LessonSync {
    static let shared = LessonSync()
    private(set) var user: String?
    func setUser(_ user: String?) {
        self.user = user
        LessonPaths.activeScope = user.map { "scope-" + $0 }
    }
    func scopeForCurrentUser(_ user: String) -> String? { "scope-" + user }
    func restoreOffline() -> Bool { false }
    func sync(force: Bool = false) async {}
}

@MainActor final class EduArchive {
    static let shared = EduArchive()
    func resetAfterAccountDeletion() {}
}

private final class IdentityProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var user = "a"
    private static var nextHeldPath: String?
    private static var held: (IdentityProtocol, Data)?
    private static var paths: [String] = []

    static func configure(user: String, hold path: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        precondition(held == nil)
        self.user = user
        nextHeldPath = path
    }
    static var isHolding: Bool {
        lock.lock(); defer { lock.unlock() }
        return held != nil
    }
    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return paths.count
    }
    static func release() {
        lock.lock()
        let response = held
        held = nil
        lock.unlock()
        precondition(response != nil)
        response!.0.finish(response!.1)
    }
    static func changeUser(_ user: String) {
        lock.lock(); defer { lock.unlock() }
        self.user = user
    }

    // Intercept every request so an unexpected endpoint can never reach the network.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "wrongbook-identity-fixture.invalid" else {
            client!.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let path = request.url!.path
        Self.lock.lock()
        Self.paths.append(path)
        let payload: [String: Any]
        switch path {
        case "/api/state": payload = ["ok": true, "u": Self.user, "nick": Self.user]
        case "/api/account_delete_request":
            payload = ["ok": true, "receipt_id": "synthetic-receipt", "status": "pending", "expected_by": "2026-10-10"]
        case "/api/account_delete_status":
            payload = ["ok": true, "receipt_id": "synthetic-receipt", "status": "completed"]
        case "/api/login", "/api/register", "/api/logout": payload = ["ok": true]
        default:
            Self.lock.unlock()
            client!.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        if Self.nextHeldPath == path {
            Self.nextHeldPath = nil
            Self.held = (self, data)
            Self.lock.unlock()
        } else {
            Self.lock.unlock()
            finish(data)
        }
    }
    private func finish(_ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct SessionIdentityRegression {
    @MainActor static func waitUntilHeld() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !IdentityProtocol.isHolding {
            precondition(Date() < deadline, "The expected production request never reached the fixture")
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    @MainActor static func assertUser(_ session: Session, _ user: String) {
        precondition(session.phase == .loggedIn)
        precondition(session.status?.user == user, "A stale response replaced the current identity")
        precondition(LessonSync.shared.user == user, "A stale response replaced the active library scope")
        precondition(!session.busy)
    }

    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let keys = ["api_base", "dev_user", "dev_pw", "accountDeletionReceipt"]
        let originals = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set("https://wrongbook-identity-fixture.invalid", forKey: "api_base")
        precondition(URLProtocol.registerClass(IdentityProtocol.self))
        defer {
            URLProtocol.unregisterClass(IdentityProtocol.self)
            for key in keys {
                if let value = originals[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let session = Session()
        await session.login(user: "a", password: "synthetic")
        assertUser(session, "a")
        IdentityProtocol.configure(user: "a", hold: "/api/state")
        let oldRefresh = Task { await session.refresh() }
        try await waitUntilHeld()
        await session.logout()
        IdentityProtocol.changeUser("b")
        await session.login(user: "b", password: "synthetic")
        IdentityProtocol.release()
        await oldRefresh.value
        assertUser(session, "b")
        print("PASS production Session.refresh: delayed A response cannot replace B after logout/login")

        let restored = Session()
        IdentityProtocol.configure(user: "a", hold: "/api/state")
        let oldRestore = Task { await restored.restore() }
        try await waitUntilHeld()
        restored.skipLogin()
        IdentityProtocol.release()
        await oldRestore.value
        precondition(restored.phase == .loggedIn && restored.status == nil && LessonSync.shared.user == nil)
        print("PASS production Session.restore: delayed response cannot replace guest choice")
        let guestCount = IdentityProtocol.requestCount
        await restored.refresh()
        precondition(IdentityProtocol.requestCount == guestCount, "Guest foreground refresh must not reuse a retained login cookie")
        precondition(restored.phase == .loggedIn && restored.status == nil && LessonSync.shared.user == nil)
        print("PASS production guest refresh: no status request and no silent re-login")

        LessonPaths.offlineReadOnly = true
        await restored.refresh()
        precondition(IdentityProtocol.requestCount == guestCount + 1)
        assertUser(restored, "a")
        LessonPaths.offlineReadOnly = false
        print("PASS production offline refresh: cached-account reconnect still probes and restores identity")

        let serialized = Session()
        serialized.phase = .loggedOut
        IdentityProtocol.configure(user: "a", hold: "/api/login")
        let login = Task { await serialized.login(user: "a", password: "synthetic") }
        try await waitUntilHeld()
        let count = IdentityProtocol.requestCount
        serialized.skipLogin()
        await serialized.login(user: "b", password: "synthetic")
        await serialized.register(email: "b@example.invalid", password: "synthetic", nick: "b")
        await serialized.logout()
        let deleted = await serialized.deleteAccount(password: "synthetic")
        await serialized.refresh()
        await serialized.refreshDeletion()
        precondition(!deleted && serialized.busy && serialized.phase == .loggedOut)
        precondition(IdentityProtocol.requestCount == count, "A busy auth operation allowed another request")
        IdentityProtocol.release()
        await login.value
        assertUser(serialized, "a")
        print("PASS production login: busy blocks guest, overlapping auth, deletion and background refresh")

        await serialized.logout()
        IdentityProtocol.configure(user: "b", hold: "/api/register")
        let registration = Task { await serialized.register(email: "b@example.invalid", password: "synthetic", nick: "b") }
        try await waitUntilHeld()
        let registrationCount = IdentityProtocol.requestCount
        serialized.skipLogin()
        await serialized.login(user: "a", password: "synthetic")
        precondition(serialized.busy && serialized.phase == .loggedOut)
        precondition(IdentityProtocol.requestCount == registrationCount)
        IdentityProtocol.release()
        await registration.value
        assertUser(serialized, "b")
        print("PASS production register: busy preserves registration until its status response completes")

        IdentityProtocol.configure(user: "b", hold: "/api/account_delete_request")
        let oldReceipt = Task { await serialized.refreshDeletion() }
        try await waitUntilHeld()
        await serialized.logout()
        IdentityProtocol.changeUser("c")
        await serialized.login(user: "c", password: "synthetic")
        IdentityProtocol.release()
        await oldReceipt.value
        assertUser(serialized, "c")
        precondition(serialized.deletionReceipt == nil)

        var receipt = try DeletionReceipt(json: ["receipt_id": "synthetic-receipt", "status": "pending"])
        receipt.owner = "c"
        receipt.scope = "scope-c"
        serialized.deletionReceipt = receipt
        IdentityProtocol.configure(user: "c", hold: "/api/account_delete_status")
        let oldCompletion = Task { await serialized.refreshDeletion() }
        try await waitUntilHeld()
        await serialized.logout()
        IdentityProtocol.changeUser("d")
        await serialized.login(user: "d", password: "synthetic")
        IdentityProtocol.release()
        await oldCompletion.value
        assertUser(serialized, "d")
        precondition(serialized.deletionReceipt?.status == "pending")
        print("PASS production deletion refresh: stale discovery/completion cannot rebind receipt or clear new user")
    }
}
