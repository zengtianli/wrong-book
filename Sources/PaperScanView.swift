import PhotosUI
import SwiftUI

/// 录卷子 —— 扫描 → 定页码 → 传到学习库。
///
/// 传完就结束，本机不留副本、不做识别。下一步在 Mac 上：
///     python3 engine/paper_ingest.py pull <slug>   →   CC 会话 /exam
///
/// 放在「我的」里而不是单开一个 tab：拍卷子是**家长**偶尔做的事，
/// 学习/错题本是孩子每天做的事。为它加第四个 tab，会让每天用的那两屏各挤窄一点。
struct PaperScanView: View {
    @EnvironmentObject var sync: LessonSync

    @State private var slug = PaperScan.Slug.todayDefault(subject: "chinese")
    @State private var nextPage = 1
    @State private var pages: [ScanPage] = []
    @State private var note = ""
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var banner: String?

    private var subjects: [(key: String, name: String)] {
        // 学科从课程包的 manifest 派生（它带 subject / subject_name）——
        // 在这儿手写一份 chinese/math 的对照表，就是 ~/Edu domains.yaml 之外的第二份。
        let g = LessonPack.load().tree.map { (key: $0.key, name: $0.name) }
        return g.isEmpty ? [("chinese", "语文"), ("math", "数学")] : g
    }

    var body: some View {
        List {
            Section("这是哪份卷子") {
                Picker("学年", selection: $slug.year) {
                    ForEach(thisYear - 2...thisYear + 1, id: \.self) {
                        // verbatim：`Text("\(2026)")` 会走本地化数字格式，显示成 **2,026**。
                        // 年份不是数量，不该有千分位。
                        Text(verbatim: "\($0)–\($0 + 1)").tag($0)
                    }
                }
                Picker("学期", selection: $slug.term) {
                    Text("上学期").tag(1); Text("下学期").tag(2)
                }
                Picker("年级", selection: $slug.grade) {
                    ForEach(1...6, id: \.self) { Text("\($0) 年级").tag($0) }
                }
                Picker("科目", selection: $slug.subject) {
                    ForEach(subjects, id: \.key) { Text($0.name).tag($0.key) }
                }
                Picker("卷种", selection: $slug.kind) {
                    ForEach(PaperScan.kinds, id: \.key) { Text($0.name).tag($0.key) }
                }
                LabeledContent("档案目录") {
                    Text(slug.text).font(.footnote.monospaced()).foregroundStyle(Ink.dim)
                }
                TextField("备注（比如「p1–p2 没拍」）", text: $note)
            }

            Section {
                Stepper("下一张算第 \(nextPage) 页", value: $nextPage, in: 1...40)
                if PaperScan.cameraAvailable {
                    Button { showCamera = true } label: {
                        Label("扫描卷子（自动找边、去畸变）", systemImage: "doc.viewfinder")
                    }
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(PaperScan.cameraAvailable ? "从相册选" : "从相册选（这台设备没有扫描器）",
                          systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("拍/选")
            } footer: {
                Text("页码是**卷子上的**页码，不是这一批的第几张 —— 只拍了 p3–p6 就从 3 开始。")
            }

            if !pages.isEmpty {
                Section("待传 \(pages.count) 页") {
                    ForEach($pages) { $p in
                        HStack(spacing: 12) {
                            Image(uiImage: p.image).resizable().scaledToFill()
                                .frame(width: 44, height: 58).clipped()
                                .overlay(Rectangle().stroke(Ink.line))
                            Stepper("第 \(p.page) 页", value: $p.page, in: 1...40)
                                .disabled(busy)
                            statusIcon(p.state)
                        }
                    }
                    .onDelete { idx in pages.remove(atOffsets: idx) }
                }
            }

            Section {
                Button {
                    Task { await upload() }
                } label: {
                    HStack {
                        if busy { ProgressView().padding(.trailing, 4) }
                        Text(busy ? "正在传…" : "传到学习库（\(pending) 页）")
                    }
                }
                .disabled(busy || pending == 0)
            } footer: {
                if let banner {
                    Text(banner).foregroundStyle(allDone ? Ink.green : Ink.red)
                } else {
                    Text("传完在 Mac 上跑 `paper_ingest.py pull \(slug.text)`，再用 /exam 录档。")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("录卷子")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Ink.paper)
        .fullScreenCover(isPresented: $showCamera) {
            PaperScan.Camera { imgs in
                showCamera = false
                add(imgs)
            }.ignoresSafeArea()
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var imgs: [UIImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self),
                       let i = UIImage(data: d) { imgs.append(i) }
                }
                add(imgs)
                picked = []
            }
        }
    }

    private var thisYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }
    private var pending: Int { pages.filter { !$0.state.isDone }.count }
    private var allDone: Bool { !pages.isEmpty && pages.allSatisfy { $0.state.isDone } }

    @ViewBuilder private func statusIcon(_ st: ScanPage.State) -> some View {
        switch st {
        case .idle:      EmptyView()
        case .uploading: ProgressView()
        case .done:      Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green)
        case .failed(let m):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Ink.red)
                .accessibilityLabel(m)
        }
    }

    /// 扫描器/相册回来的图按当前页码依次编号，并把「下一张算第几页」推到后面。
    private func add(_ imgs: [UIImage]) {
        guard !imgs.isEmpty else { return }          // 取消扫描回的是空数组，不是错误
        for i in imgs {
            pages.append(ScanPage(page: nextPage, image: i))
            nextPage += 1
        }
        banner = nil
    }

    /// 逐页传。**已经传成功的不重传** —— 中途断网重按一次只补没传上去的那几页，
    /// 而不是把服务端上已有的页再覆盖一遍（覆盖本身是允许的，只是白烧流量）。
    private func upload() async {
        busy = true
        banner = nil
        defer { busy = false }

        // 同一页码传两次 = 后一张把前一张覆盖掉，而且**不会有任何报错**。
        // 传之前就拦住，比传完发现少一页强。
        let nums = pages.filter { !$0.state.isDone }.map(\.page)
        if Set(nums).count != nums.count {
            banner = "有两张标了同一个页码 —— 先改掉再传"
            return
        }

        for idx in pages.indices where !pages[idx].state.isDone {
            pages[idx].state = .uploading
            guard let d = PaperScan.jpeg(pages[idx].image) else {
                // 压不下去不是「传失败」，是这张图本身太满 —— 说清楚该怎么办。
                pages[idx].state = .failed("压不到 3MB 以内")
                continue
            }
            do {
                try await Api.paperPage(slug: slug.text, page: pages[idx].page,
                                        jpeg: d, note: note)
                pages[idx].state = .done
            } catch {
                pages[idx].state = .failed(error.localizedDescription)
            }
        }
        // 失败清单先拼好再放进字符串 —— 插值里塞多行闭包 Swift 解析不了
        let bad: [String] = pages.compactMap { p in
            if case .failed(let m) = p.state { return "p\(p.page) \(m)" }
            return nil
        }
        banner = bad.isEmpty
            ? "✅ \(pages.count) 页都传上去了 —— 在 Mac 上跑 paper_ingest.py pull \(slug.text)"
            : "\(bad.count) 页没传上去（其余已成功）：" + bad.joined(separator: "；")
    }
}
