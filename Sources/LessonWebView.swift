import SwiftUI
import WebKit

/// 练习引擎的承载层 —— **不重写 practice.js，原样跑它**。
///
/// `~/Edu/engine/practice.js` 1271 行里装着判题 verify()、组卷权重 nextGen()、
/// 错题本两层结构、勋章判定 PRED、上瘾机制五件套；题库是**内联进每个 HTML** 的。
/// 用 SwiftUI 重写 = 第二份判题逻辑，和 bank.db / badges.json 必然漂移，
/// 而 ~/Edu 那些硬约束（「改了 badges.json 必须全量重渲」「页面内联题数必须等于库里的数」）
/// 在 Swift 侧根本继承不了。
///
/// ## 为什么用 loadSimulatedRequest 而不是 loadFileURL
///
/// 页面是**完全自包含**的（JS/CSS/题库全内联，零 CDN —— ~/Edu 的既定设计），
/// 唯一的外部依赖是三个相对请求：`/api/state` `/api/practice` `/api/archive`，
/// 由内联的 `points_client.js` 自己发。
///
/// 用 `file://` 载入的话：① `points_client.js` 第一行就 `return`（它只在 http(s) 下工作）
/// ② 相对 URL 会解析成 `file:///api/state`。于是得分和存档同步全断，
/// **而且不报错** —— 页面照常能做题，只是分永远不涨。
///
/// `loadSimulatedRequest` 把 bundle 里的 HTML 挂在真实的 `https://edu.tianli.cyou/<路径>` 源上：
/// 页面内容离线来自包里，相对请求走真网络。没网时 `points_client.js` 自己 catch 掉
/// （它本来就 fail-soft），做题完全不受影响 —— 这正是想要的降级。
///
/// **所以这里没有「桥」**：得分、存档同步都是网页自己干的，原样。
/// 唯一一条 Swift→JS 之外的消息是 `submitted`（交卷了），只为让原生刷新一次余额。
/// 每加一条消息就是一处「原生和网页各存一份状态」的机会 —— 加之前先问
/// 「这件事能不能在网页里自己完成」，能就不加。
struct LessonWebView: UIViewRepresentable {
    let lesson: Lesson
    /// 进来是干什么的 —— 正常做题，还是从错题本进来复习某一类。
    var entry: LessonEntry = .normal
    /// 交卷后回调（引擎算完这一套的对错之后）。原生借此刷新余额 / 触发庆祝。
    var onSubmitted: () -> Void = {}
    /// 复习入口的结果。**组不出来时必须说** —— 静默给一套普通题，
    /// 孩子以为在补错题，其实没有。
    var onEntryResult: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmitted: onSubmitted, onEntryResult: onEntryResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = LessonPaths.webDataStore
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "edu")
        ucc.addUserScript(WKUserScript(source: Self.probe,
                                       injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true))
        // 复习入口挂成 **user script** 而不是 didFinish 之后 evaluate 一次：
        // points_client.js 在服务端存档更新时会 location.reload()，
        // 只 evaluate 一次的话那一下会把刚组好的错题卷冲掉，而页面看着一切正常。
        if let js = entry.injectedJS {
            ucc.addUserScript(WKUserScript(source: js,
                                           injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
        }
        cfg.userContentController = ucc
        #if os(iOS)
        // 做题要发声（practice.js 用 WebAudio 合成音效），别要求全屏手势
        cfg.allowsInlineMediaPlayback = true
        #endif

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        context.coordinator.watchForBackground(wv)
        #if os(iOS)
        wv.isOpaque = false                       // Mac 上 isOpaque 只读、无 backgroundColor、无 scrollView
        wv.backgroundColor = .clear
        wv.scrollView.contentInsetAdjustmentBehavior = .always
        #else
        wv.setValue(false, forKey: "drawsBackground")   // Mac 的透明底：WebKit 的私有但稳定的开关
        #endif
        context.coordinator.load(into: wv, lesson: lesson)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.onSubmitted = onSubmitted
        context.coordinator.onEntryResult = onEntryResult
        context.coordinator.load(into: wv, lesson: lesson)   // 换课才重载，内部按 slug 去重
    }

    /// 注入的探针：只报告「交卷了」，不改引擎任何行为。
    ///
    /// 和 `points_client.js` 同一种接法 —— document 上的**捕获**监听。
    /// 绑在按钮上会失效：引擎重绘题卡时按钮整个被换掉。
    private static let probe = """
    (function () {
      document.addEventListener('click', function (e) {
        var t = e.target;
        if (!t || t.id !== 'submitSet') return;
        setTimeout(function () {
          try {
            var rows = document.querySelectorAll('#review .rrow').length;
            var ok = document.querySelectorAll('#review .mk.ok').length;
            if (!rows) return;
            window.webkit.messageHandlers.edu.postMessage({ k: 'submitted', rows: rows, ok: ok });
          } catch (err) {}
        }, 1200);   // 比 points_client 的 600ms 晚，让它先把这笔分记上去
      }, true);
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onSubmitted: () -> Void
        var onEntryResult: (String) -> Void
        private var loadedSlug: String?
        private var currentLesson: Lesson?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .reload, let lesson = currentLesson {
                decisionHandler(.cancel)
                loadedSlug = nil
                load(into: webView, lesson: lesson)
            } else { decisionHandler(.allow) }
        }

        init(onSubmitted: @escaping () -> Void, onEntryResult: @escaping (String) -> Void) {
            self.onSubmitted = onSubmitted
            self.onEntryResult = onEntryResult
        }

        deinit { if let o = bgObserver { NotificationCenter.default.removeObserver(o) } }

        private weak var live: WKWebView?
        private var bgObserver: NSObjectProtocol?

        /// 切后台前**显式落一次档**。
        ///
        /// 不做这件事的表现：孩子刚做完一套就按 Home 键，进度没了 —— 而且不报错。
        /// 原因是 WebView 被挂起时 JS 定时器停摆，`points_client.js` 的 15 秒轮询和
        /// `pagehide` 都指望不上（iOS 上 WebView 进后台未必派发 pagehide）。
        ///
        /// **不是第二条同步通路**：调的就是 `points_client.js` 自己的 `pushArc`
        /// （属主守卫 / 拉取基线 / 就绪标志一条不绕），且走 `sendBeacon` ——
        /// 交给网络进程发，WebView 挂起也照发完。
        func watchForBackground(_ wv: WKWebView) {
            live = wv
            bgObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                    guard let wv = self?.live else { return }
                    wv.evaluateJavaScript(
                        "(window.__EDU_POINTS__ && window.__EDU_POINTS__.flush(true)) || 'noclient'")
            }
        }

        func load(into wv: WKWebView, lesson: Lesson) {
            currentLesson = lesson
            guard loadedSlug != lesson.slug else { return }
            guard let u = lesson.resolvedURL,
                  let html = try? String(contentsOf: u, encoding: .utf8) else {
                // 静默白屏是最难查的一种 —— 明说是哪一课、缺在哪
                let msg = "这份个人课程暂不可用，请返回学习页重新同步。"
                wv.loadHTMLString(
                    "<meta name=viewport content='width=device-width,initial-scale=1'>"
                    + "<pre style='padding:24px;font:15px/1.7 -apple-system;white-space:pre-wrap'>"
                    + msg + "</pre>", baseURL: nil)
                loadedSlug = lesson.slug
                return
            }
            loadedSlug = lesson.slug
            // origin 必须是账本那台机器：页面里的 /api/* 是相对路径，靠它解析。
            // Api.base 可被 launch 参数指向本地 server（验证用），这里跟着它走。
            let url = Api.base.appendingPathComponent(lesson.file)
            let offlinePolicy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; connect-src 'none'; form-action 'none';\">"
            wv.loadSimulatedRequest(URLRequest(url: url), responseHTML: LessonPaths.offlineReadOnly ? offlinePolicy + html : html)
        }

        func userContentController(_ c: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any] else { return }
            switch d["k"] as? String {
            case "submitted": onSubmitted()
            case "review":    onEntryResult(d["r"] as? String ?? "")
            default:          break
            }
        }
    }
}

/// 把 URLSession 的登录 cookie 借给 WebView。
///
/// 两边各有一套 cookie 存储：原生请求用 `URLSession.shared`（HttpOnly 会话就在那），
/// WebView 用 `WKWebsiteDataStore`。不搬的话表现是：**app 里已登录，网页里没登录** ——
/// 页面照常能做题，只是积分徽章不出现、分不涨、存档不同步，**一句报错都没有**。
enum WebSession {
    static func handOff() async {
        guard !LessonPaths.offlineReadOnly else { return }
        guard let host = Api.base.host,
              let cookies = HTTPCookieStorage.shared.cookies(for: Api.base) else { return }
        let store = LessonPaths.webDataStore.httpCookieStore
        for c in cookies where c.domain.contains(host) || host.contains(c.domain.dropFirst(c.domain.hasPrefix(".") ? 1 : 0)) {
            await store.setCookie(c)
        }
    }
}

/// 进这一课是干什么的。
///
/// **不是**由原生去点页面上的按钮实现的 —— 那等于拿 `#gens` 里的第几个当参数传，
/// 改一次版面排序就悄悄点到别的题型上，而且不报错。走引擎自己的显式入口
/// `window.__PRACTICE__.review(gid)`（`~/Edu/engine/practice.js`），
/// 由引擎组卷、由引擎决定出什么题。
enum LessonEntry: Equatable {
    /// 正常做题，引擎按自己的权重组一套混合卷
    case normal
    /// 组一套错题卷 —— 每条错题记录出一道**同型新题**
    case wrongSet
    /// 只练这一类（从错题本某一条点进来）
    case drill(gid: String)

    var injectedJS: String? {
        let arg: String
        switch self {
        case .normal:          return nil
        case .wrongSet:        arg = "null"
        case .drill(let gid):
            let d = try? JSONSerialization.data(withJSONObject: [gid])
            let a = d.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            arg = String(a.dropFirst().dropLast())        // 用 JSON 编码转义，别自己拼引号
        }
        return """
        (function () {
          function post(r) {
            try { window.webkit.messageHandlers.edu.postMessage({ k: 'review', r: r }); } catch (e) {}
          }
          var P = window.__PRACTICE__;
          if (!P || typeof P.review !== 'function') { post('noentry'); return; }
          try { post(P.review(\(arg)) || 'gone'); } catch (e) { post('threw'); }
        })();
        """
    }

    /// 引擎回的结果翻译成一句人话。返回 nil = 组出来的正是想要的，不用打扰。
    static func complaint(for result: String) -> String? {
        switch result {
        case "drill", "wrong": return nil
        case "mix":    return "错题本里没有还在题库里的题型 —— 给你出了一套常规的"
        case "gone":   return "这类题已不在当前个人课程中，请同步课程后重试"
        case "noentry":return "这一课的页面是旧版渲染的，没有复习入口 —— 重新构建一次就有了"
        case "threw":  return "引擎组卷时报错了"
        default:       return "复习入口没回话（\(result.isEmpty ? "空" : result)）"
        }
    }
}
