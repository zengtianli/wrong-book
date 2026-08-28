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
                                timeout: TimeInterval = 20) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
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
