import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import VisionKit

/// 整卷扫描 —— 把一份卷子一页页传到学习库；服务端每收一页就自动读错题、入库。
///
/// **这一屏为什么值得做成原生**，就一条：`VNDocumentCameraViewController`。
/// 卷子是文档不是风景 —— 手机浏览器只能调普通相机，拍出来是斜的、有阴影、边不齐，
/// 而读图那步要认的是密密麻麻的题干和红笔批改，畸变直接变成「读出一道错的题」。
/// 系统这个扫描器白送：自动找边 + 去透视 + 多页 + 当场重拍 + 拍完排序。
///
/// **它自己不读图、不判题、不入库** —— 那些在服务端，和网页 `wrong.html` 是同一条链
/// （`points/server.py::paper_page` → `engine/wrong_worker.py` → `wrong_ingest.py auto`）。
/// 这边只传图 + 等结果。扫描件同时留在 `papers/`，Mac 上想做整卷复盘再
/// `paper_ingest.py pull <slug>` + `/exam`（可选，不是必经）。
enum PaperScan {

    // MARK: - 卷子的身份 = 档案目录名

    /// slug 就是 `~/Edu/archive/` 下的目录名，服务端按同一条白名单正则收
    /// （`points/server.py` 的 `PAPER_SLUG_RE`）。**两边必须能对上**：
    /// 这边拼错了，表现是传的时候报「卷子编号不对」，而不是传上去落错地方。
    struct Slug: Equatable {
        var year: Int                   // 学年起始年，2026 = 2026-2027 学年
        var term: Int                   // 1 = 上学期，2 = 下学期
        var grade: Int                  // 1...6
        var subject: String             // domains.yaml 的 key（chinese / math），从课程包派生
        var kind: String                // 卷种 key

        var text: String { "\(year)s\(term)-g\(grade)-\(subject)-\(kind)" }

        /// 今天该默认落在哪个学年学期。9 月~次年 1 月 = 上学期；2~7 月 = 下学期。
        /// 8 月是暑假尾巴，按「马上开学」算进新学年上学期 —— 这时候拍的多半是上学期末的卷子，
        /// 但目录名要的是**这份卷子属于哪个学期**，所以用户改得动比默认猜得准更重要。
        static func todayDefault(subject: String) -> Slug {
            let c = Calendar(identifier: .gregorian)
            let now = Date()
            let m = c.component(.month, from: now), y = c.component(.year, from: now)
            let term = (m >= 8 || m == 1) ? 1 : 2
            let year = (m >= 8) ? y : y - 1
            return Slug(year: year, term: term, grade: 3, subject: subject, kind: "final")
        }
    }

    /// 卷种。**这是这一屏独有的词表** —— ~/Edu 侧没有它的 SSOT（archive 目录名里才第一次出现），
    /// 所以在这儿定义，不是从别处抄来的第二份。加一种就在这儿加一行。
    static let kinds: [(key: String, name: String)] = [
        ("final", "期末卷"), ("mid", "期中卷"),
        ("unit", "单元卷"), ("quiz", "随堂/小测"),
    ]

    // MARK: - 压图

    /// 上传前压到服务端收得下（`WRONG_MAX` 3MB）。
    ///
    /// **阶梯有地板，宁可传不了也不压糊**（照搬 ~/Edu 2026-08-16 拿真扫描件量出来的结论）：
    /// 1200px/q55 那一档实测已经把字典框小字压到崩边缘，而压糊的题不会报错，
    /// 只会让读图那步读出一道**错的**题。所以到底装不下就明说，让人把这一页单独拍一张。
    static func jpeg(_ img: UIImage, limit: Int = 2_900_000) -> Data? {
        for (edge, q) in [(2400.0, 0.82), (2000.0, 0.78), (1700.0, 0.72)] {
            guard let d = shrink(img, edge: edge)?.jpegData(compressionQuality: q) else { continue }
            if d.count <= limit { return d }
        }
        return nil
    }

    private static func shrink(_ img: UIImage, edge: Double) -> UIImage? {
        let w = img.size.width, h = img.size.height
        let long = max(w, h)
        guard long > 0 else { return nil }
        let k = long > edge ? edge / long : 1.0
        if k == 1.0 { return img }
        let size = CGSize(width: w * k, height: h * k)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1                     // 别乘 screen scale：那会让「长边 2400」实际变成 7200
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - 系统文档扫描器

    /// 真机上有没有这个能力。
    ///
    /// ⚠ **`isSupported` 在模拟器上也返回 true**（2026-08-31 截图实测：模拟器里
    /// 「扫描卷子」照样亮着）—— 而模拟器没有相机，点下去只有一片黑。所以显式排除
    /// 模拟器，让它退到相册选图这条路：一个点了没反应的按钮比没有这个按钮更糟。
    static var cameraAvailable: Bool {
        #if targetEnvironment(simulator) || !os(iOS)
        return false                    // 模拟器没相机；Mac 没有 VNDocumentCamera（走相册/文件选图那条路）
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }

    #if !os(iOS)
    /// Mac 上没有文档扫描器 —— 保留同名类型让调用点不变，cameraAvailable=false 保证它永远不被弹出。
    struct Camera: View {
        var onDone: ([UIImage]) -> Void
        var body: some View { EmptyView() }
    }
    #else
    struct Camera: UIViewControllerRepresentable {
        var onDone: ([UIImage]) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }
        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let vc = VNDocumentCameraViewController()
            vc.delegate = context.coordinator
            return vc
        }
        func updateUIViewController(_ v: VNDocumentCameraViewController, context: Context) {}

        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            let onDone: ([UIImage]) -> Void
            init(onDone: @escaping ([UIImage]) -> Void) { self.onDone = onDone }

            func documentCameraViewController(_ c: VNDocumentCameraViewController,
                                              didFinishWith scan: VNDocumentCameraScan) {
                onDone((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            }
            // 取消和出错都要回一个空数组：不回的话界面永远停在「扫描中」，
            // 表现是「点了没反应」——而实际上是我们没收场。
            func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) {
                onDone([])
            }
            func documentCameraViewController(_ c: VNDocumentCameraViewController,
                                              didFailWithError error: Error) {
                onDone([])
            }
        }
    }
    #endif
}

/// 一页待传的图。页码是**卷子上的真页码**，不是它在这一批里的序号 ——
/// `archive/README` 里那份就是「p1–p2 未拍」，只归了 p3–p6。
struct ScanPage: Identifiable, Equatable {
    let id = UUID()
    var page: Int
    var image: UIImage
    var state: State = .idle
    var log = ""                 // 服务端读图那步的原样输出（给人看细节，不参与判断）
    var got: Int?                // 「录进题库 N 道」—— 从 log 里摘的，服务端算的
    var skipped: Int?

    enum State: Equatable {
        case idle, uploading
        case uploaded(job: String?)   // 传上了。job 为 nil = 存档了但没派上自动读图
        case reading(Int)             // 服务端读图中，已等 N 秒
        case done(String)             // 读完，括号里是给人看的一句
        case failed(String)           // 没传上去（会被重传）
        case readFailed(String)       // 传上了但读图没成（不重传：图在服务端，重传只会再读一遍）

        /// 服务端已经有这一页了 —— 再按「传」也不该重传。
        var isUploaded: Bool {
            switch self {
            case .idle, .uploading, .failed: return false
            default: return true
            }
        }
        var isBad: Bool {
            switch self {
            case .failed, .readFailed: return true
            default: return false
            }
        }
    }

    static func == (a: ScanPage, b: ScanPage) -> Bool { a.id == b.id && a.state == b.state }
}


/// 验证通道：`-papertest 1` 时跑一遍**真实上传路径**并把结果显示出来。
///
/// 为什么要有它：这一屏最容易错的不是布局，是「压出来的图服务端收不收」——
/// dataURL 前缀、字段名、大小上限，任何一处对不上都表现为一句笼统的 400。
/// 而这条路人得用手点相册才走得到，**人点得到、机器截不到的东西等于没验过**。
///
/// 它跑的是 `PaperScan.jpeg` + `Api.paperPage` 本身，不是照着它们重写一遍 ——
/// 重写的那种「实测」测的是替身，会假绿。
struct PaperSelfTest: View {
    @State private var lines: [String] = ["准备…"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.footnote.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding()
        }
        .background(Ink.paper)
        .task { await run() }
    }

    private func run() async {
        let d = UserDefaults.standard
        let user = d.string(forKey: "papertest_user") ?? ""
        let pw = d.string(forKey: "papertest_pw") ?? ""
        let slug = d.string(forKey: "papertest_slug") ?? "2026s1-g3-chinese-final"
        lines = ["base = \(Api.base.absoluteString)", "user = \(user)"]

        do {
            try await Api.login(user: user, password: pw)
            lines.append("✅ 登录")
        } catch {
            lines.append("❌ 登录：\(error.localizedDescription)"); return
        }

        // 合成一张「像卷子」的图：纯色压出来只有几 KB，走不到压图阶梯的任何一档，
        // 那样的绿证明不了真照片传得上去。画满噪点+线条让它有真实的熵。
        let size = CGSize(width: 2200, height: 3000)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<4000 {
                UIColor(hue: CGFloat(i % 97) / 97, saturation: 0.7, brightness: 0.5, alpha: 1).setFill()
                ctx.fill(CGRect(x: CGFloat((i * 37) % 2100), y: CGFloat((i * 61) % 2900),
                                width: 40, height: 14))
            }
        }
        guard let jpg = PaperScan.jpeg(img) else {
            lines.append("❌ 压图：三档都没压到 3MB 以内"); return
        }
        lines.append("✅ 压图 \(jpg.count / 1000)KB")

        // ① 传输层 + 字段：auto:false —— 噪点图不该为这一步烧读图
        do {
            let r = try await Api.paperPage(slug: slug, page: 7, jpeg: jpg, note: "papertest", auto: false)
            lines.append(r.job == nil ? "✅ 上传 \(slug) p7（auto:false，未派读图）"
                                      : "❌ auto:false 还是派了作业 \(r.job!)")
        } catch {
            lines.append("❌ 上传：\(error.localizedDescription)"); return
        }
        // ② 坏 slug 必须被服务端挡回来 —— 这条绿了才说明白名单真的在生效
        //    ⚠ 只有服务端那句「卷子编号不对」才算被拒 —— 超时/断网也是 error，
        //    2026-09-01 实测模拟器上行慢到 90s 超时，这条曾把超时当成「被拒」报了绿。
        do {
            _ = try await Api.paperPage(slug: "../etc", page: 1, jpeg: jpg, auto: false)
            lines.append("❌ 坏 slug 竟然被收了")
        } catch {
            let m = error.localizedDescription
            lines.append(m.contains("卷子编号不对") ? "✅ 坏 slug 被拒：\(m)"
                                                : "❌ 坏 slug 没到服务端就失败了（不算被拒）：\(m)")
        }
        // ③ 真派一次自动读图并轮询到完 —— 走的就是 PaperScanView 那条路（Api.job）。
        //    烧一次读图是它的价格；噪点图读出「没读到做错的题」就是对的答案。
        //    `-papertest_noauto 1` 跳过这步（只想验传输层时）。
        var wrongId: String?
        if !d.bool(forKey: "papertest_noauto") {
            do {
                let r = try await Api.paperPage(slug: slug, page: 8, jpeg: jpg, note: "papertest")
                guard let job = r.job else {
                    lines.append("❌ 没派上自动读图：\(r.autoErr ?? "无说明")"); return
                }
                wrongId = r.wrongId
                lines.append("✅ 上传 p8 → 登记 \(r.wrongId ?? "?") · 作业 \(job)")
                lines.append("⏳ 读图中 0s")
                var sec = 0
                poll: while true {
                    switch try await Api.job(job) {
                    case .running:
                        try? await Task.sleep(for: .seconds(3)); sec += 3
                        lines[lines.count - 1] = "⏳ 读图中 \(sec)s"
                        if sec > 600 { lines[lines.count - 1] = "❌ 10 分钟没等到结果"; break poll }
                    case .done(let ok, let log):
                        let (g, k) = PaperScanView.counts(in: log)
                        lines[lines.count - 1] = (ok ? "✅" : "❌") + " 读图 \(sec)s：" +
                            PaperScanView.summary(log, got: g, skipped: k)
                        lines.append(String(log.suffix(300)))
                        break poll
                    }
                }
            } catch {
                lines.append("❌ 自动读图那条：\(error.localizedDescription)")
            }
        }
        // ④ 收尾：自己留下的东西自己删（批次 + 错题图），别让生产上攒 papertest 垃圾
        do {
            try await Api.paperDel(slug: slug)
            if let wrongId { try await Api.wrongDel(id: wrongId) }
            lines.append("✅ 收尾：批次与错题图已删")
        } catch {
            lines.append("⚠️ 收尾没删干净：\(error.localizedDescription)")
        }
        lines.append("DONE")
    }
}
