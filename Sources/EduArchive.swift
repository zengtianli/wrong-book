import Foundation
import WebKit

/// 学习进度存档的**原生读取口** —— 只读，从不写。
///
/// ## 数据在哪
///
/// 练习引擎 `~/Edu/engine/practice.js` 把「这一课练得怎么样」写进 localStorage 的
/// `edu:<slug>`（掌握度 / 错题本 / 今日计数），把「这孩子整体走到哪」写进
/// `edu:@profile`（经验 / 等级 / 连续天数 / 勋章 / 今日任务）。那是它的 SSOT。
///
/// ## 为什么原生不另存一份
///
/// 存了就是第二份状态。孩子在网页里连着订正 2 次把一类题划掉，原生那份不知道 ——
/// 表现是「错题本里那条一直在」，**而且一句报错都没有**。所以这里只读引擎写的那一份。
///
/// ## 怎么读到同一份
///
/// WebView 的 localStorage 按 **origin** 分区。练习页是用 `loadSimulatedRequest`
/// 挂在 `Api.base` 那个 origin 上的（见 `LessonWebView` 顶部说明）。
/// 这里起一个离屏 WKWebView，用**同一个** `WKWebsiteDataStore.default()`、
/// **同一个** origin 载入一张空白页，于是 `localStorage` 就是引擎刚写的那一份。
///
/// ⚠ 换服务器（`-api_base` 指向本地 server 做验证）= 换 origin = 换一份 localStorage。
/// 这不是 bug，是 Web 的分区语义；所以 origin 变了要把宿主页重载一次。
@MainActor
final class EduArchive {
    static let shared = EduArchive()

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var webView: WKWebView?
    private var hostedOrigin: String?
    /// 同一时刻只允许一次载入，重入的调用等同一个 Task（避免起一堆 WebView）
    private var loading: Task<WKWebView, Error>?
    private let nav = Nav()

    private init() {}

    func resetAfterAccountDeletion() {
        loading?.cancel()
        loading = nil
        webView?.stopLoading()
        webView = nil
        hostedOrigin = nil
    }

    /// 取一份快照：所有 `edu:` 开头的键。拿不到就抛，**不返回空字典** ——
    /// 「读失败」和「档案是空的」长得一模一样，混起来就永远查不出是哪种。
    func snapshot() async throws -> [String: String] {
        guard LessonPaths.activeScope != nil else { return [:] }
        let wv = try await host()
        let js = """
        (function () {
          var o = {};
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (k && k.indexOf('edu:') === 0) o[k] = localStorage.getItem(k);
          }
          return JSON.stringify(o);
        })()
        """
        let raw = try await wv.evaluateJavaScript(js)
        guard let s = raw as? String, let d = s.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] else {
            throw Failure(message: "存档读回来的不是 JSON —— WebView 里的 localStorage 取不到")
        }
        return o
    }

    private func host() async throws -> WKWebView {
        let origin = Api.base.absoluteString
        if let wv = webView, hostedOrigin == origin { return wv }
        if let t = loading { return try await t.value }

        let t = Task { () throws -> WKWebView in
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = LessonPaths.webDataStore          // 和练习页同一个存储分区
            let wv = WKWebView(frame: .zero, configuration: cfg)
            wv.navigationDelegate = nav
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                nav.finish = { err in
                    if let err { c.resume(throwing: err) } else { c.resume() }
                }
                // 空白页，只为把 origin 定在账本那台机器上 —— 不发任何网络请求
                wv.loadSimulatedRequest(URLRequest(url: Api.base.appendingPathComponent("__archive__")),
                                        responseHTML: "<!doctype html><meta charset=utf-8><title>archive</title>")
            }
            return wv
        }
        loading = t
        do {
            let wv = try await t.value
            webView = wv
            hostedOrigin = origin
            loading = nil
            return wv
        } catch {
            loading = nil
            throw error
        }
    }

    /// 导航完成的一次性回调。用类而不是闭包属性直接挂在 self 上，
    /// 是因为 `WKNavigationDelegate` 是 weak 引用 —— 挂在临时对象上会被提前释放，
    /// 表现是**永远等不到回调**（比报错难查）。
    private final class Nav: NSObject, WKNavigationDelegate {
        var finish: ((Error?) -> Void)?
        private func done(_ e: Error?) { let f = finish; finish = nil; f?(e) }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done(nil) }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { done(e) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!,
                     withError e: Error) { done(e) }
    }
}
