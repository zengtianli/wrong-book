// Compile with Sources/{LessonSync,Lessons}.swift. No production HTTP or accounts.
import Foundation
import WebKit

enum Api {
    static let base = URL(string: "https://personal-library.invalid")!
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
@MainActor final class EduArchive {
    static let shared = EduArchive()
    func resetAfterAccountDeletion() {}
}
final class FixtureProtocol: URLProtocol {
    static var response: [String: Any] = [:]
    static let page = Data("<!doctype html><title>Original synthetic fixture</title>".utf8)
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == Api.base.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        let data = path == "/api/lessons" ? try! JSONSerialization.data(withJSONObject: Self.response) : Self.page
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct PersonalLibraryTest {
    @MainActor static func main() async throws {
        URLProtocol.registerClass(FixtureProtocol.self)
        let sync = LessonSync()
        let scopeA = "fixture-a-" + UUID().uuidString
        let scopeB = "fixture-b-" + UUID().uuidString
        defer {
            for scope in [scopeA, scopeB] {
                let url = LessonPaths.directory(scope: scope)
                if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
            }
        }
        assert(LessonPack.load().lessons.isEmpty)
        await sync.sync(force: true)
        assert(FixtureProtocol.paths.isEmpty, "Guest must not download")
        let row: [String: Any] = ["slug": "synthetic", "file": "synthetic.html", "sha256": FixtureProtocol.page.sha256Hex]
        FixtureProtocol.response = ["owner": "a", "scope": scopeA, "lessons": [row]]
        sync.setUser("a")
        await sync.sync(force: true)
        let lessonA = LessonPack.load().lessons.first!
        assert(lessonA.resolvedURL != nil)
        let storeA = LessonPaths.webDataStore.identifier
        sync.setUser("b")
        assert(LessonPack.load().lessons.isEmpty && lessonA.resolvedURL == nil)
        await sync.sync(force: true) // stale owner A response must be rejected
        assert(LessonPaths.activeScope == nil)
        FixtureProtocol.response = ["owner": "b", "lessons": [row]]
        await sync.sync(force: true) // missing account instance must be rejected
        assert(LessonPaths.activeScope == nil)
        FixtureProtocol.response = ["owner": "b", "scope": scopeB, "lessons": []]
        await sync.sync(force: true)
        assert(LessonPack.load().lessons.isEmpty && LessonPack.load().problem == nil)
        assert(LessonPaths.webDataStore.identifier != storeA)
        assert(FileManager.default.fileExists(atPath: LessonPaths.directory(scope: scopeA).appendingPathComponent("synthetic.html").path))
        for file in ["../secret.html", "/secret.html", "a/../secret.html", "a\\secret.html", "manifest.json"] {
            assert(!LessonPaths.valid(file))
        }
        FixtureProtocol.response = ["owner": "b", "scope": scopeB, "lessons": [["slug": "bad", "file": "../secret.html", "sha256": FixtureProtocol.page.sha256Hex]]]
        await sync.sync(force: true)
        assert(LessonPack.load().lessons.isEmpty)
        FixtureProtocol.response = ["owner": "b", "scope": scopeB, "lessons": [["slug": "bad", "file": "bad.html", "sha256": String(repeating: "0", count: 64)]]]
        await sync.sync(force: true)
        assert(LessonPack.load().lessons.isEmpty)
        sync.setUser(nil)
        assert(LessonPack.load().lessons.isEmpty && lessonA.resolvedURL == nil)
        assert(FixtureProtocol.paths.allSatisfy { $0 == "/api/lessons" || $0 == "/api/lesson" })
        print("PASS: guest empty, account ownership, mandatory scope, separate WebKit stores, preserved old account cache, traversal/hash rejection, no global downloads")
    }
}
