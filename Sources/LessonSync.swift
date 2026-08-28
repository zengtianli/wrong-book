import CryptoKit
import Foundation

/// 练习页的增量更新 —— 站上改了课 / 加了课，app 下次启动就拿到新版。
///
/// ## 为什么下载源是 `/app/` 而不是 `/primary-*/`
///
/// 站上那份公开页面在剥离之后**又注入了反馈浮标和 noindex**
/// （`~/Edu/engine/deploy.py` 的 `assemble()`，那是全站唯一注入点）。
/// 而 bundle 里这份是 `app_pack.py` 只剥不注的产物 —— **同一课、同一内容，
/// 两边 sha256 必不相等**（2026-08-28 实测 9/9 全不等，每篇恰好差 14921 字节）。
/// 拿 bundle 的 sha 去比站上那份，结论永远是「每课都变了」，每次启动全量重下。
///
/// 所以 `deploy.py` 会把 `app_pack` 的产物**原样**发一份到 `site/app/`：
/// 下载的字节和 bundle 里的字节由同一段代码产出，对得上是结构保证，不是巧合。
///
/// ## fail-closed：要么整包对上，要么一个字节都不启用
///
/// 任何一课校验不过 / 下不下来 → **不写清单**，继续用上一份一致的状态。
/// 半包比不更新更糟：app 里那一课点不开，或者做的是上一版的题，**都不报错**。
@MainActor
final class LessonSync: ObservableObject {
    static let shared = LessonSync()

    /// 上一次同步的结果，给「学习」页显示一行。nil = 还没跑过。
    @Published private(set) var note: String?
    @Published private(set) var running = false

    private let dir: URL
    private var lastRun: Date?

    /// `baseDir` 只为测试注入 —— 不注入的话回归会写进真的 Application Support，
    /// 上一次运行的残留会让「更新成功」假绿。（抄 blog-reader 的 Store 那条。）
    init(baseDir: URL? = nil) {
        dir = baseDir.map { LessonPaths.dir(under: $0) } ?? LessonPaths.downloads
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var manifestURL: URL { dir.appendingPathComponent("manifest.json") }
    func fileURL(_ rel: String) -> URL { dir.appendingPathComponent(rel) }

    /// 拉一次。没网 / 拉不到就安静地什么都不做 —— 离线是常态，不是故障。
    func sync(force: Bool = false) async {
        guard !running else { return }
        // 前台切换会连着触发好几次，10 分钟内不重复拉
        if !force, let t = lastRun, Date().timeIntervalSince(t) < 600 { return }
        running = true
        defer { running = false; lastRun = Date() }

        let remote: [String: Any]
        do {
            remote = try await fetchJSON(Api.base.appendingPathComponent("app/manifest.json"))
        } catch {
            note = nil                       // 拉不到清单 = 离线，不当故障说
            return
        }
        guard let lessons = remote["lessons"] as? [[String: Any]], !lessons.isEmpty else {
            note = "站上的课程清单是空的 —— 没有更新"
            return
        }

        let bundleSha = Self.bundleShaBySlug()
        var fetched = 0, problems: [String] = []

        for L in lessons {
            guard let slug = L["slug"] as? String,
                  let rel = L["file"] as? String,
                  let want = L["sha256"] as? String, !want.isEmpty else {
                problems.append("清单里有一条缺 slug/file/sha256")
                continue
            }
            // 已经有对得上的了 —— 下载过的那份，或者 bundle 里本来就是这一版
            if let have = try? Data(contentsOf: fileURL(rel)), have.sha256Hex == want { continue }
            if bundleSha[slug] == want { continue }

            do {
                let data = try await fetchData(Api.base.appendingPathComponent("app/" + rel))
                // **下完必须验**。校验不过最常见的原因不是「文件坏了」，
                // 而是拿回来一张登录页（HTTP 200，内容是 HTML，只是不是这一课）。
                guard data.sha256Hex == want else {
                    problems.append("\(slug)：下下来的和清单说的对不上（拿到登录页？）")
                    continue
                }
                let dst = fileURL(rel)
                try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: dst, options: .atomic)
                fetched += 1
            } catch {
                problems.append("\(slug)：下不下来（\(error.localizedDescription)）")
            }
        }

        // fail-closed：只要有一课没落实，就**不换清单**，继续用上一份一致的状态。
        // 换了清单而某课没有文件 = 那一课点进去白屏，而且不报错。
        if !problems.isEmpty {
            note = "更新没做完，仍在用上一版：" + problems.prefix(2).joined(separator: "；")
            return
        }
        do {
            let d = try JSONSerialization.data(withJSONObject: remote,
                                               options: [.prettyPrinted, .sortedKeys])
            try d.write(to: manifestURL, options: .atomic)
            note = fetched > 0 ? "更新了 \(fetched) 课" : nil
        } catch {
            note = "清单写不进去：\(error.localizedDescription)"
        }
    }

    /// 把下载的那份全丢掉，回到随包发的版本。（出问题时的逃生门。）
    func reset() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        note = "已回到随包发的那一版"
    }

    // MARK: - 取

    private func fetchJSON(_ url: URL) async throws -> [String: Any] {
        let d = try await fetchData(url)
        guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            throw Api.Failure(message: "清单不是 JSON")
        }
        return o
    }

    private func fetchData(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData     // 别拿 URLCache 里的旧副本来判"没变"
        let (d, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Api.Failure(message: "HTTP \(code)") }
        return d
    }

    /// bundle 里那份 manifest 记的 sha —— 用来判「这一课本来就是最新的，不用下」。
    static func bundleShaBySlug() -> [String: String] {
        guard let u = Bundle.main.url(forResource: "Lessons/manifest", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let list = o["lessons"] as? [[String: Any]] else { return [:] }
        var m: [String: String] = [:]
        for L in list {
            if let s = L["slug"] as? String, let h = L["sha256"] as? String { m[s] = h }
        }
        return m
    }
}

/// 下载副本的落点。**纯路径计算，没有状态** —— 所以 `Lesson` 那边
/// 解析页面位置时可以直接用，不必去碰 `LessonSync` 这个 @MainActor 单例。
enum LessonPaths {
    static func dir(under base: URL) -> URL {
        base.appendingPathComponent("points-deck/Lessons", isDirectory: true)
    }
    /// 不用 Caches：iOS 空间紧张时会自己清掉它 —— 那正好会在最需要离线的时候
    /// 把离线能力拿走，而离线做题是这个 app 存在的理由。
    static let downloads: URL = dir(under: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
}

extension Data {
    /// 下载校验用的是**文件字节**的摘要，不是「先转成字符串再 hash」——
    /// 后者一遇编码差异就飘，而页面全是中文。
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
