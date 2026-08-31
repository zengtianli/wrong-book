import Foundation
import SwiftUI
import UIKit
import VisionKit

/// 整卷扫描 —— 把一份卷子拍成 `archive/<slug>/scans/pN.*`，供 Mac 上的 `/exam` 录档。
///
/// **这一屏为什么值得做成原生**，就一条：`VNDocumentCameraViewController`。
/// 卷子是文档不是风景 —— 手机浏览器只能调普通相机，拍出来是斜的、有阴影、边不齐，
/// 而读图那步要认的是密密麻麻的题干和红笔批改，畸变直接变成「读出一道错的题」。
/// 系统这个扫描器白送：自动找边 + 去透视 + 多页 + 当场重拍 + 拍完排序。
///
/// **它不读图、不判题、不入库。** 图传到 VPS 就结束，剩下的全在 Mac：
///     paper_ingest.py pull <slug>   →   CC 会话 /exam
/// 原因见 `~/Edu/engine/paper_ingest.py` 的模块注释（同一条分工）。
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
        #if targetEnvironment(simulator)
        return false
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }

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
}

/// 一页待传的图。页码是**卷子上的真页码**，不是它在这一批里的序号 ——
/// `archive/README` 里那份就是「p1–p2 未拍」，只归了 p3–p6。
struct ScanPage: Identifiable, Equatable {
    let id = UUID()
    var page: Int
    var image: UIImage
    var state: State = .idle

    enum State: Equatable {
        case idle, uploading, done, failed(String)

        var isDone: Bool { self == .done }
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

        do {
            try await Api.paperPage(slug: slug, page: 7, jpeg: jpg, note: "papertest")
            lines.append("✅ 上传 \(slug) p7")
        } catch {
            lines.append("❌ 上传：\(error.localizedDescription)"); return
        }
        // 坏 slug 必须被服务端挡回来 —— 这条绿了才说明白名单真的在生效
        do {
            try await Api.paperPage(slug: "../etc", page: 1, jpeg: jpg)
            lines.append("❌ 坏 slug 竟然被收了")
        } catch {
            lines.append("✅ 坏 slug 被拒：\(error.localizedDescription)")
        }
        lines.append("DONE")
    }
}
