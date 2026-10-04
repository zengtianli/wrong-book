import Foundation
import Combine

// Supplemental original acceptance evidence: compile LessonSync/LessonPaths/Api/PaperRequestSession unchanged. Only the unrelated
// WebKit archive reset boundary is a fixture; no archive/WebKit/account-service claim.
@MainActor final class EduArchive {
    static let shared = EduArchive()
    private(set) var resets = 0
    func resetAfterAccountDeletion() { resets += 1 }
}

private final class CacheFixtureProtocol: URLProtocol {
    static let host = "wrongbook-lesson-cache-fixture.invalid"
    private static let lock = NSLock()
    private static var manifest = Data()
    private static var page = Data()
    private static var arrivals: [[String: String]] = []

    static func configure(manifest: Data, page: Data) {
        lock.lock(); defer { lock.unlock() }
        self.manifest = manifest; self.page = page
    }
    static var requests: [[String: String]] {
        lock.lock(); defer { lock.unlock() }; return arrivals
    }
    // Intercept every request, including mistakes: nothing may fall through to a live service.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        Self.arrivals.append(["url": request.url?.absoluteString ?? "", "cookie": cookie,
                              "handles_cookies": String(request.httpShouldHandleCookies)])
        let url = request.url!
        let allowed = url.host == Self.host && cookie == "edu_sess=isolated-cache-fixture"
        let data = url.path == "/api/lessons" ? Self.manifest : Self.page
        let file = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "file" }?.value
        let pathAllowed = url.path == "/api/lessons" || (url.path == "/api/lesson" && file == "unit-a.html")
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: allowed && pathAllowed ? 200 : 403,
                                       httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: allowed && pathAllowed ? data : Data("fixture refused unexpected request".utf8))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct LessonCacheRecoveryAcceptance {
    struct Rejected: Error { let message: String }
    @MainActor static func require(_ passed: Bool, _ message: String) throws {
        if !passed { throw Rejected(message: message) }
    }
    static func manifest(owner: String, scope: String, page: Data, sha: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["owner": owner, "scope": scope,
            "lessons": [["file": "unit-a.html", "sha256": sha ?? page.sha256Hex]]], options: [.sortedKeys])
    }

    @MainActor static func main() async {
        do { try await run() }
        catch { print("FAIL real LessonSync cache: \(error)"); exit(1) }
    }

    @MainActor static func run() async throws {
        let arguments = UserDefaults.standard
        guard let stage = arguments.string(forKey: "cache_qa_stage"), ["save", "restore"].contains(stage),
              let runID = arguments.string(forKey: "cache_qa_run"), UUID(uuidString: runID) != nil,
              let output = arguments.string(forKey: "cache_qa_output") else {
            throw Rejected(message: "explicit isolated stage/run/output required")
        }
        let scope = "wrongbook-cache-qa-" + runID
        let user = "cache-fixture-" + runID
        let suite = "WrongBook.LessonCacheQA." + runID
        let defaults = UserDefaults(suiteName: suite)!
        let key = "privateLibraryLastAuthenticatedV2"
        let directory = LessonPaths.directory(scope: scope)
        let manifestFile = directory.appendingPathComponent("manifest.json")
        let pageFile = directory.appendingPathComponent("unit-a.html")
        let proof = URL(fileURLWithPath: output, isDirectory: true)
        let page = Data("<!doctype html><html><body><h1>Isolated course</h1><p>synthetic exercise</p></body></html>".utf8)
        let original = try manifest(owner: user, scope: scope, page: page)
        var checks: [String] = []

        if stage == "save" {
            try require(!FileManager.default.fileExists(atPath: directory.path), "UUID cache must not preexist")
            try require(defaults.dictionary(forKey: key) == nil, "UUID preference suite must be new")
            try require(Api.base.host == CacheFixtureProtocol.host, "production Api.base must be fixture-only")
            let cookie = HTTPCookie(properties: [.domain: CacheFixtureProtocol.host, .path: "/",
                .name: "edu_sess", .value: "isolated-cache-fixture"])!
            HTTPCookieStorage.shared.setCookie(cookie)
            try require(URLProtocol.registerClass(CacheFixtureProtocol.self), "fixture transport registration failed")
            defer {
                URLProtocol.unregisterClass(CacheFixtureProtocol.self)
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            CacheFixtureProtocol.configure(manifest: original, page: page)
            let sync = LessonSync(defaults: defaults)
            sync.setUser(user)
            // This fixture starts after identity confirmation, with an authenticated scope/cookie.
            // Actual PaperRequestSession binds the request; no real authentication server is tested.
            LessonPaths.activeScope = scope
            let account = try PaperRequestSession.capture()
            await sync.sync(force: true, account: account)
            try require(sync.note == "个人课程已同步", "production sync failed: " + (sync.note ?? "no note"))
            try require(try Data(contentsOf: pageFile) == page, "production sync must persist exact downloaded HTML")
            try require(try Data(contentsOf: manifestFile) == original, "production sync must publish exact manifest")
            try require(defaults.dictionary(forKey: key)?["owner"] as? String == user
                        && defaults.dictionary(forKey: key)?["scope"] as? String == scope, "production offline pointer missing")
            try require(LessonPaths.activeScope == scope && !LessonPaths.offlineReadOnly, "authenticated scope not active")
            checks.append("production_sync_page_manifest_and_offline_pointer")

            // Use the actual bound authenticated request snapshot, not a replacement session.
            let badPage = Data("downloaded bytes do not match claimed digest".utf8)
            let badManifest = try manifest(owner: user, scope: scope, page: badPage, sha: String(repeating: "0", count: 64))
            CacheFixtureProtocol.configure(manifest: badManifest, page: badPage)
            let revision = sync.revision
            await sync.sync(force: true, account: account)
            try require(sync.note?.contains("课程下载校验失败") == true, "bad digest must fail through production sync")
            try require(try Data(contentsOf: pageFile) == page && Data(contentsOf: manifestFile) == original,
                        "failed download must preserve previously saved page and manifest")
            try require(sync.revision == revision && LessonPaths.activeScope == scope
                        && defaults.dictionary(forKey: key)?["scope"] as? String == scope, "failed sync changed active cache/pointer")
            checks.append("bad_download_sha_preserves_prior_cache_and_pointer")
            let requests = CacheFixtureProtocol.requests
            try require(requests.count == 4 && requests.allSatisfy { $0["cookie"] == "edu_sess=isolated-cache-fixture" },
                        "all four actual HTTP requests must stay authenticated and fixture-only")
            try require(requests.allSatisfy { $0["handles_cookies"] == "false" }, "bound request must keep captured cookie")
            try JSONSerialization.data(withJSONObject: requests, options: [.prettyPrinted, .sortedKeys])
                .write(to: proof.appendingPathComponent("requests.json"), options: .atomic)
            try original.write(to: proof.appendingPathComponent("saved-manifest.json"), options: .atomic)
            try page.write(to: proof.appendingPathComponent("saved-page.html"), options: .atomic)
            try require(defaults.synchronize(), "offline pointer must persist for next process")
        } else {
            try require(LessonPaths.activeScope == nil && !LessonPaths.offlineReadOnly, "fresh process must start with no active cache")
            let restored = LessonSync(defaults: defaults)
            try require(restored.restoreOffline(), "fresh process production restoreOffline rejected saved cache")
            try require(LessonPaths.activeScope == scope && LessonPaths.offlineReadOnly, "restored cache must be read-only")
            try require(restored.scopeForCurrentUser(user) == scope && restored.scopeForCurrentUser("other-fixture") == nil,
                        "offline cache must remain owner-scoped")
            try require(try Data(contentsOf: pageFile) == page && Data(contentsOf: manifestFile) == original,
                        "fresh process must read exact saved bytes")
            checks.append("fresh_process_restore_offline_read_only_owner_scoped")
            let revision = restored.revision
            var mismatch = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            mismatch["owner"] = "other-fixture"
            let wrongOwner = try JSONSerialization.data(withJSONObject: mismatch)
            mismatch["owner"] = user; mismatch["scope"] = "other-scope"
            let wrongScope = try JSONSerialization.data(withJSONObject: mismatch)
            for (label, data) in [("corrupt_manifest", Data("{invalid-json".utf8)),
                                  ("mismatched_owner", wrongOwner), ("mismatched_scope", wrongScope)] {
                try data.write(to: manifestFile, options: .atomic)
                try require(!restored.restoreOffline(), label + " must be rejected")
                try require(restored.revision == revision && LessonPaths.activeScope == scope && LessonPaths.offlineReadOnly,
                            label + " must preserve existing in-memory scope")
                try require(defaults.dictionary(forKey: key)?["scope"] as? String == scope && Data(contentsOf: pageFile) == page,
                            label + " must not alter pointer or saved page")
                checks.append(label + "_rejected_without_replacing_active_cache")
            }
            try original.write(to: manifestFile, options: .atomic)
            restored.reset()
            try require(LessonPaths.activeScope == nil && defaults.dictionary(forKey: key) == nil, "reset must disable offline pointer")
            try require(!LessonSync(defaults: defaults).restoreOffline(), "reset cache must not auto-activate")
            try require(try Data(contentsOf: pageFile) == page && Data(contentsOf: manifestFile) == original,
                        "reset must preserve personal files")
            checks.append("production_reset_disables_pointer_and_keeps_saved_files")
            // Only this UUID-owned fixture scope and preference suite are removed.
            try LessonPaths.removeFiles(scope: scope)
            defaults.removePersistentDomain(forName: suite)
            try require(!FileManager.default.fileExists(atPath: directory.path), "owned fixture cleanup failed")
        }
        let value: [String: Any] = ["ok": true, "stage": stage, "pid": ProcessInfo.processInfo.processIdentifier,
            "run_id": runID, "scope": scope, "suite": suite, "cache_directory": directory.path,
            "manifest_sha256": original.sha256Hex, "page_sha256": page.sha256Hex, "checks": checks,
            "identity_boundary": "already-authenticated isolated user/scope/cookie fixture; real PaperRequestSession binding",
            "uncovered": ["real account/network service", "WebKit/EduArchive behavior", "device UI"]]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: proof.appendingPathComponent(stage + ".json"), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
    }
}
