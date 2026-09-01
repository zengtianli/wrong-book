import Foundation

/// 学习库的账号客户端 —— **只管登录态**。
///
/// 这个 app 不记账、不算分：刷题积分是**练习页自己**在算（页面里内联的
/// `points/points_client.js` 监听交卷、POST `/api/practice`，每日上限在服务端），
/// 学习存档也是它在同步（`/api/archive`）。原生这边一行都不掺和 ——
/// 掺和就成了第二条通路，两条路给出不同答案时根本查不清谁对。
///
/// 原生要 cookie 干两件事：① 判断「进来的是谁 / 要不要显示登录页」
/// ② 把 cookie 借给 WebView（见 `WebSession.handOff`），否则页面里是未登录状态，
/// **页面照常能做题，只是分不涨、存档不同步，一句报错都没有**。
enum Api {
    /// 默认线上。可用 launch 参数指向本地 server 做验证：
    ///   `xcrun simctl launch <udid> cyou.tianli.wrongbook -api_base http://127.0.0.1:8799`
    /// 走 UserDefaults 而不是 `#if DEBUG` 的写死地址 —— 写死那种改一次要重编一次，
    /// 而且很容易连着发版一起漏出去。
    static var base: URL {
        if let s = UserDefaults.standard.string(forKey: "api_base"), let u = URL(string: s) {
            return u
        }
        return URL(string: "https://edu.tianli.cyou")!
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 服务端发的是 HttpOnly cookie，URLSession 的共享存储会自己带上并持久化。
    /// 我们**不碰** cookie 的值 —— 碰了就等于在 app 里复制一份会话状态。
    private static func request(_ path: String, body: [String: Any]? = nil,
                                query: [String: String]? = nil,
                                timeout: TimeInterval = 20) async throws -> [String: Any] {
        var url = base.appendingPathComponent(path)
        if let query, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = c.url ?? url
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure(message: code == 200 ? "服务端返回的不是 JSON" : "连不上学习库(HTTP \(code))")
        }
        if obj["ok"] as? Bool != true {
            // 服务端的 err 是给人看的中文，原样透出去比包一层「请求失败」有用
            throw Failure(message: obj["err"] as? String ?? "学习库拒绝了这次请求(HTTP \(code))")
        }
        return obj
    }

    static func login(user: String, password: String) async throws {
        _ = try await request("api/login", body: ["u": user, "p": password])
    }

    static func logout() async {
        _ = try? await request("api/logout", body: [:])
    }

    /// 传一页卷子回来的东西：服务端顺手把这页登记成了一张错题图并派了自动读图，
    /// `job` 就是那件作业的号（拿它去 `job(_:)` 轮询）。`job == nil` 时看 `autoErr` ——
    /// 页是存下了，只是没派上读图（比如待录入积压到了上限）。
    struct PaperUpload {
        let wrongId: String?
        let job: String?
        let autoErr: String?
    }

    /// 传一份卷子的**一页**（整卷扫描）。一页一个请求 —— 六页塞进一个 body 就是十几兆，
    /// 断线得从第一页重来。服务端同一条口径，见 `points/server.py::paper_page` 的注释。
    ///
    /// `slug` 必须过服务端那条白名单正则；拼错了这里会拿到「卷子编号不对」的 400，
    /// 而不是悄悄落到别的目录 —— 那是它要挡的事。
    ///
    /// 2026-09-01 起服务端收到一页就走网页单题那条**全自动**链（读整页错题 → 逐道入库），
    /// 返回值里带作业号。`auto: false` 只给自检通道用 —— 合成的噪点图不该烧一次读图。
    static func paperPage(slug: String, page: Int, jpeg: Data, note: String = "",
                          auto: Bool = true) async throws -> PaperUpload {
        var body: [String: Any] = [
            "slug": slug, "page": page, "note": note,
            "data": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
        ]
        if !auto { body["auto"] = false }
        let r = try await request("api/paper_page", body: body, timeout: 90)  // 3MB 走手机网络，20 秒不够
        return PaperUpload(wrongId: r["wrong_id"] as? String, job: r["job"] as? String,
                           autoErr: r["auto_err"] as? String)
    }

    enum JobState {
        case running
        case done(ok: Bool, log: String)
    }

    /// 轮询一件读图/入库作业。读图在服务端要 30~120 秒，这里只问「完了没」，
    /// 结果那段 `log` 是 `wrong_ingest.py auto` 的原样输出 —— 「录进题库 N 道」那句
    /// 是它算的，界面只摘不数（两处各数一遍迟早对不上，和 wrong.html 同一条原则）。
    static func job(_ id: String) async throws -> JobState {
        let r = try await request("api/job", query: ["id": id])
        guard (r["state"] as? String) == "done", let res = r["res"] as? [String: Any] else {
            return .running
        }
        return .done(ok: res["ok"] as? Bool == true, log: res["log"] as? String ?? "")
    }

    /// 撤一张登记过的错题图（自检通道收尾用；真删，服务端不留底）。
    static func wrongDel(id: String) async throws {
        _ = try await request("api/wrong_del", body: ["id": id])
    }

    /// 撤卷子的一页（不给 page 就撤整批）。同上，自检收尾用。
    static func paperDel(slug: String, page: Int? = nil) async throws {
        var body: [String: Any] = ["slug": slug]
        if let page { body["page"] = page }
        _ = try await request("api/paper_del", body: body)
    }

    /// 会话探活 + 顺带取几个**回显**用的数。
    ///
    /// ⚠ 这里的 `practiceLeft` / `balance` 一律**原样回显服务端算好的值**，
    /// 原生不做任何加减。~/Edu 的口径：分值一律服务端算，请求里报什么都不算数。
    static func status(timeout: TimeInterval = 20) async throws -> Status {
        Status(json: try await request("api/state", timeout: timeout))
    }
}

/// `/api/state` 里这个 app 用得上的那几个字段。
/// 用不上的（rules/shop/entries/house…）**不解析** —— 解析了就得维护，
/// 而它们属于另一个 app（京宝积分）的职责。
struct Status {
    let user: String
    let nick: String
    let balance: Int
    /// 今天刷题还能挣多少分。服务端算的，这里只显示。
    let practiceLeft: Int

    init(json o: [String: Any]) {
        user = o["u"] as? String ?? ""
        nick = o["nick"] as? String ?? ""
        balance = o["balance"] as? Int ?? 0
        practiceLeft = o["practice_left"] as? Int ?? 0
    }
}
