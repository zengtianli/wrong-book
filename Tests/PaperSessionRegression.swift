import Foundation

// The production API and request binding are compiled unchanged. Only local-library state
// is isolated; every HTTP operation uses the real Api.paperPage / Api.job through URLProtocol.
enum LessonPaths {
    static var offlineReadOnly = false
    static var activeScope: String?
}

private final class RecordingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    static var onArrival: (() -> Void)?

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let action = Self.onArrival
        Self.onArrival = nil
        Self.lock.unlock()
        action?()
        let payload: String
        if request.url?.path == "/api/job" {
            payload = #"{"ok":true,"state":"done","res":{"ok":true,"log":"synthetic result"}}"#
        } else {
            payload = #"{"ok":true,"job":"fixture-job","wrong_id":"fixture-wrong"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: Data(payload.utf8))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct PaperSessionRegression {
    static let origin = URL(string: "https://wrongbook-upload-fixture.invalid")!

    static func cookie(_ value: String) -> HTTPCookie {
        HTTPCookie(properties: [.domain: origin.host!, .path: "/", .name: "edu_sess", .value: value])!
    }

    @MainActor static func rejected(_ action: () async throws -> Void) async {
        let count = RecordingProtocol.requests.count
        do { try await action(); fatalError("A changed import session was accepted") }
        catch is PaperRequestSession.Changed {}
        catch { fatalError("Unexpected failure: \(type(of: error))") }
        precondition(RecordingProtocol.requests.count == count, "Rejected work must not reach the transport")
    }

    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let oldBase = defaults.object(forKey: "api_base")
        defaults.set(origin.absoluteString, forKey: "api_base")
        defer {
            if let oldBase { defaults.set(oldBase, forKey: "api_base") }
            else { defaults.removeObject(forKey: "api_base") }
            for cookie in HTTPCookieStorage.shared.cookies(for: origin) ?? [] {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }

        await rejected { _ = try PaperRequestSession.capture() }
        LessonPaths.activeScope = "scope-a"
        HTTPCookieStorage.shared.setCookie(cookie("synthetic-a"))
        let account = try PaperRequestSession.capture()
        let uploaded = try await Api.paperPage(slug: "2026s1-g3-math-final", page: 1,
                                               jpeg: Data([0xff, 0xd8, 0xff, 0xd9]),
                                               account: account, transport: transport)
        precondition(uploaded.job == "fixture-job")
        precondition(RecordingProtocol.requests.last?.value(forHTTPHeaderField: "Cookie") == "edu_sess=synthetic-a")
        precondition(RecordingProtocol.requests.last?.httpShouldHandleCookies == false)
        if case .done(let ok, _) = try await Api.job("fixture-job", account: account, transport: transport) {
            precondition(ok)
        } else { fatalError("The bound job did not complete") }

        LessonPaths.activeScope = "scope-b"
        await rejected {
            _ = try await Api.paperPage(slug: "2026s1-g3-math-final", page: 2, jpeg: Data([1]),
                                       account: account, transport: transport)
        }
        await rejected { _ = try await Api.job("fixture-job", account: account, transport: transport) }

        LessonPaths.activeScope = "scope-a"
        HTTPCookieStorage.shared.setCookie(cookie("synthetic-new-login"))
        await rejected {
            _ = try await Api.paperPage(slug: "2026s1-g3-math-final", page: 2, jpeg: Data([1]),
                                       account: account, transport: transport)
        }

        // Switch after request binding, at the real transport boundary. The in-flight POST
        // must still carry A's cookie, and the next operation must be rejected before HTTP.
        HTTPCookieStorage.shared.setCookie(cookie("synthetic-a"))
        RecordingProtocol.onArrival = {
            HTTPCookieStorage.shared.setCookie(cookie("synthetic-b"))
            LessonPaths.activeScope = "scope-b"
        }
        _ = try await Api.paperPage(slug: "2026s1-g3-math-final", page: 3, jpeg: Data([1]),
                                   account: account, transport: transport)
        precondition(RecordingProtocol.requests.last?.value(forHTTPHeaderField: "Cookie") == "edu_sess=synthetic-a")
        await rejected { try account.requireCurrent() }
        await rejected { _ = try await Api.job("fixture-job", account: account, transport: transport) }

        LessonPaths.activeScope = "scope-a"
        HTTPCookieStorage.shared.setCookie(cookie("synthetic-a"))
        LessonPaths.offlineReadOnly = true
        await rejected { _ = try PaperRequestSession.capture() }
        LessonPaths.offlineReadOnly = false
        defaults.set("https://another-fixture.invalid", forKey: "api_base")
        await rejected { _ = try await Api.job("fixture-job", account: account, transport: transport) }
        print("PASS real paperPage/job: original cookie bound; changed scope, renewed login and endpoint blocked before HTTP")
        print("PASS switch at transport boundary: in-flight request stays with original account; following requests blocked")
    }
}
