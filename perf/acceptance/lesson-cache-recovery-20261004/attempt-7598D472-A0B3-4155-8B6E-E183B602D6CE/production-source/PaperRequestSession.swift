import Foundation

/// An import batch uses only the account and cookie with which the user started it.
/// This transient snapshot is never persisted; HTTPCookieStorage remains the login source.
struct PaperRequestSession {
    private let origin: URL
    private let scope: String
    private let cookieHeader: String

    struct Changed: LocalizedError {
        var errorDescription: String? {
            "账号未确认或登录状态已改变，已停止本批次。请先登录并同步个人资料，再重新导入。"
        }
    }

    // points/server.py: COOKIE = "edu_sess", Path=/.
    private static func currentCookie(for origin: URL) -> String? {
        let cookies = (HTTPCookieStorage.shared.cookies(for: origin) ?? [])
            .filter { $0.name == "edu_sess" && !$0.value.isEmpty }
        guard cookies.count == 1 else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    @MainActor static func capture() throws -> PaperRequestSession {
        guard !LessonPaths.offlineReadOnly,
              let scope = LessonPaths.activeScope,
              let cookie = currentCookie(for: Api.base) else { throw Changed() }
        return PaperRequestSession(origin: Api.base, scope: scope, cookieHeader: cookie)
    }

    @MainActor func requireCurrent() throws {
        guard Api.base == origin, !LessonPaths.offlineReadOnly,
              LessonPaths.activeScope == scope,
              Self.currentCookie(for: origin) == cookieHeader else { throw Changed() }
    }

    @MainActor func bound(_ request: URLRequest) throws -> URLRequest {
        try requireCurrent()
        guard let url = request.url,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port else {
            throw Changed()
        }
        var request = request
        // A later account switch cannot make URLSession substitute the new account's cookie
        // between the check above and the actual request. In-flight work stays with its owner.
        request.httpShouldHandleCookies = false
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        return request
    }
}
