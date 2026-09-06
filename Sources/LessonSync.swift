import CryptoKit
import Foundation
import WebKit

/// Only authenticated, account-instance-scoped content can become active.
@MainActor
final class LessonSync: ObservableObject {
    static let shared = LessonSync()
    @Published private(set) var note: String?
    @Published private(set) var running = false
    @Published private(set) var revision = 0
    private var owner: String?
    private var generation = UUID()
    private var lastRun: Date?
    private let defaults: UserDefaults
    private let offlineKey = "privateLibraryLastAuthenticatedV2"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func scopeForCurrentUser(_ user: String) -> String? {
        if owner == user { return LessonPaths.activeScope }
        let pointer = defaults.dictionary(forKey: offlineKey)
        return pointer?["owner"] as? String == user ? pointer?["scope"] as? String : nil
    }

    /// Restores only the last authenticated account's local cache, never network authority.
    func restoreOffline() -> Bool {
        guard let pointer = defaults.dictionary(forKey: offlineKey),
              let user = pointer["owner"] as? String,
              let scope = pointer["scope"] as? String,
              let data = try? Data(contentsOf: LessonPaths.directory(scope: scope).appendingPathComponent("manifest.json")),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              manifest["owner"] as? String == user, manifest["scope"] as? String == scope else { return false }
        owner = nil
        LessonPaths.activeScope = scope
        LessonPaths.offlineReadOnly = true
        note = "离线模式：仅使用本机资料；登录联网后可上传和同步。"
        revision += 1
        return true
    }

    func setUser(_ user: String?) {
        if user == nil { defaults.removeObject(forKey: offlineKey) }
        guard owner != user || LessonPaths.offlineReadOnly else { return }
        // A new authenticated session must confirm its instance before offline reuse.
        defaults.removeObject(forKey: offlineKey)
        owner = user
        LessonPaths.offlineReadOnly = false
        note = nil
        generation = UUID()
        lastRun = nil
        LessonPaths.activeScope = nil
        EduArchive.shared.resetAfterAccountDeletion()
        revision += 1
    }

    func sync(force: Bool = false) async {
        guard let user = owner, !running else { return }
        if !force, let date = lastRun, Date().timeIntervalSince(date) < 600 { return }
        let token = generation
        running = true
        defer {
            running = false
            if token != generation { Task { await self.sync(force: true) } }
        }
        do {
            let data = try await fetchData(Api.base.appendingPathComponent("api/lessons"))
            guard let remote = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  remote["owner"] as? String == user,
                  let scope = remote["scope"] as? String, !scope.isEmpty,
                  let lessons = remote["lessons"] as? [[String: Any]] else {
                throw Api.Failure(message: "个人课程清单缺少账号校验信息")
            }
            guard token == generation else { return }
            let dir = LessonPaths.directory(scope: scope)
            var files = Set<String>()
            for lesson in lessons {
                guard let file = lesson["file"] as? String, LessonPaths.valid(file),
                      files.insert(file).inserted,
                      let sha = lesson["sha256"] as? String, sha.count == 64 else {
                    throw Api.Failure(message: "个人课程文件校验信息无效")
                }
                let target = dir.appendingPathComponent(file)
                if let old = try? Data(contentsOf: target), old.sha256Hex == sha { continue }
                var url = URLComponents(url: Api.base.appendingPathComponent("api/lesson"), resolvingAgainstBaseURL: false)!
                url.queryItems = [URLQueryItem(name: "file", value: file)]
                let page = try await fetchData(url.url!)
                guard token == generation else { return }
                guard page.sha256Hex == sha else { throw Api.Failure(message: "课程下载校验失败") }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try page.write(to: target, options: .atomic)
            }
            guard token == generation else { return }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
            if LessonPaths.activeScope != scope { EduArchive.shared.resetAfterAccountDeletion() }
            LessonPaths.activeScope = scope
            defaults.set(["owner": user, "scope": scope], forKey: offlineKey)
            revision += 1
            lastRun = Date()
            note = lessons.isEmpty ? nil : "个人课程已同步"
        } catch {
            if token == generation { note = "暂时无法同步个人课程：" + error.localizedDescription }
        }
    }

    func reset() {
        // Keep personal files; disable the active copy until authenticated sync.
        LessonPaths.activeScope = nil
        defaults.removeObject(forKey: offlineKey)
        lastRun = nil
        EduArchive.shared.resetAfterAccountDeletion()
        revision += 1
        note = "已停用本机课程副本，可重新同步个人课程"
    }

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Api.Failure(message: "请检查网络与登录状态")
        }
        return data
    }
}

enum LessonPaths {
    static var activeScope: String?
    static var offlineReadOnly = false
    static func valid(_ file: String) -> Bool {
        !file.isEmpty && !file.hasPrefix("/") && !file.contains("\\") &&
        !file.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) &&
        file.hasSuffix(".html")
    }
    static func directory(scope: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wrong-book/private-v2/" + Data(scope.utf8).sha256Hex, isDirectory: true)
    }
    static var downloads: URL? { activeScope.map(directory(scope:)) }
    // Never read the historical default localStorage/cookies.
    static var webDataStore: WKWebsiteDataStore {
        guard let scope = activeScope else { return guestStore }
        return webDataStore(scope: scope)
    }
    static func webDataStore(scope: String) -> WKWebsiteDataStore {
        let chars = Array(String(Data(("wrong-book:" + scope).utf8).sha256Hex.prefix(32)))
        let uuid = [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-")
        return WKWebsiteDataStore(forIdentifier: UUID(uuidString: uuid)!)
    }
    static func removeFiles(scope: String) throws {
        let directory = directory(scope: scope)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private static let guestStore = WKWebsiteDataStore.nonPersistent()
}

extension Data {
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
