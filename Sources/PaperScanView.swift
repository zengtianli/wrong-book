import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 录卷子 —— 扫描 → 定页码 → 传到学习库 → **等服务端把这页的错题读完、入库**。
///
/// 2026-09-01 起（用户拍板「web 是正品，app 是附属」）这一屏和网页 `wrong.html` 是**同一条链**：
/// 每一页传上去，服务端就登记成一张错题图、派自动读图，读到的错题全部进题库，
/// 归不到课的进「待归类」。这边只多做一件事：把「录进 N 道 / 跳过 M 道」画在屏上。
/// 扫描件同时留在 `papers/` —— 想做整卷复盘（失分归轴）再在 Mac 上
/// `paper_ingest.py pull <slug>` + `/exam`，那是可选的，不再是必经的门。
///
/// iPhone/iPad 只提供拍照和相册；Mac 使用文件选图。
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
    @State private var showUploadConsent = false
    @State private var aiEnabled = false
    @State private var showFiles = false
    @State private var detailsExpanded = false
    @State private var preview: ScanPage?

    private var subjects: [(key: String, name: String)] {
        // 已有课程只提供名称，不能把尚未导入过的学科从入口中移除。
        ImportSubjectOptions.merging(LessonPack.load().tree.map { (key: $0.key, name: $0.name) })
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                Text("图片导入").font(.system(size: 24, weight: .semibold)).foregroundStyle(Ink.text)
                #if os(iOS)
                Text("拍下错题或从相册选择，识别后核对原图，再开始复习。")
                    .font(.caption).foregroundStyle(Ink.dim)
                #else
                Text("选择错题图片，识别后核对原图，再开始复习。")
                    .font(.caption).foregroundStyle(Ink.dim)
                #endif
                HStack(spacing: 12) {
                    #if os(iOS)
                    Button {
                        Task {
                            if await PaperScan.requestCameraAccess() { showCamera = true }
                            else { banner = "无法使用相机。请在系统设置中允许错题本访问相机，或从相册选择。" }
                        }
                    } label: { Label("拍照", systemImage: "camera") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!PaperScan.cameraAvailable)
                    PhotosPicker(selection: $picked, matching: .images) { Label("相册", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.bordered)
                    #else
                    Button { showFiles = true } label: { Label("选择图片", systemImage: "photo.badge.plus") }
                        .buttonStyle(.borderedProminent).keyboardShortcut("o", modifiers: .command)
                    #endif
                }.disabled(busy)
                Picker("科目", selection: $slug.subject) {
                    ForEach(subjects, id: \.key) { Text($0.name).tag($0.key) }
                }
                .disabled(busy || pages.contains { $0.state.isUploaded })
                Text("上传前请确认科目，识别后的题目将按此归类。")
                    .font(.caption).foregroundStyle(Ink.dim)
                TextField("备注（选填）", text: $note).disabled(busy)
                }
            }
            AIAccessSection(enabled: $aiEnabled)
            Section {
                DisclosureGroup("试卷信息与页码（选填）", isExpanded: $detailsExpanded) {
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
                Picker("卷种", selection: $slug.kind) {
                    ForEach(PaperScan.kinds, id: \.key) { Text($0.name).tag($0.key) }
                }
                Stepper("下一张算第 \(nextPage) 页", value: $nextPage, in: 1...40)
                }
            }.disabled(busy || pages.contains { $0.state.isUploaded })

            if !pages.isEmpty {
                Section(pagesTitle) {
                    ForEach($pages) { $p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Button { preview = p } label: {
                                    Image(uiImage: p.image).resizable().scaledToFill()
                                        .frame(width: 44, height: 58).clipped()
                                        .overlay(Rectangle().stroke(Ink.line))
                                }.buttonStyle(.plain).accessibilityLabel("查看第 \(p.page) 页原图")
                                Stepper("第 \(p.page) 页", value: $p.page, in: 1...40)
                                    .disabled(busy || p.state.isUploaded)
                                statusIcon(p.state)
                            }
                            if let line = statusLine(p.state) {
                                Text(line).font(.footnote)
                                    .foregroundStyle(p.state.isBad ? Ink.red : Ink.dim)
                            }
                            if !p.log.isEmpty {
                                DisclosureGroup("读图记录") {
                                    Text(p.log).font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.font(.footnote)
                            }
                        }
                    }
                    .onDelete { idx in if !busy { pages.remove(atOffsets: idx) } }
                }
            }

            Section {
                Button {
                    showUploadConsent = true
                } label: {
                    HStack {
                        if busy { ProgressView().padding(.trailing, 4) }
                        Text(busy ? busyLabel : "开始识别 · \(pending) 张")
                    }
                }
                .disabled(busy || pending == 0 || !aiEnabled)
            } footer: {
                if let banner {
                    Text(banner).foregroundStyle(hasBad ? Ink.red : Ink.green)
                } else {
                    Text("识别完成后在错题本中查看。读不清的题会在结果里说明，请对照原图核对。")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("导入")
        .listStyle(.plain)
        .font(.system(size: 14))
        .environment(\.defaultMinListRowHeight, 36)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Ink.paper)
        .tint(Ink.accent)
        .sheet(item: $preview) { page in
            VStack(spacing: 12) {
                HStack { Text("第 \(page.page) 页原图").font(.headline); Spacer(); Button("完成") { preview = nil } }
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: page.image).resizable().scaledToFit().frame(width: 900)
                }
                if !page.log.isEmpty { ScrollView { Text(page.log).font(.caption).textSelection(.enabled) }.frame(maxHeight: 140) }
            }.padding(16).frame(minWidth: 320, minHeight: 420).background(Ink.paper)
        }
        #if !os(iOS)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                var images: [UIImage] = []
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let image = UIImage(data: data) else { throw Api.Failure(message: "图片无法读取：\(url.lastPathComponent)") }
                    images.append(image)
                }
                add(images)
            } catch { banner = error.localizedDescription }
        }
        #endif
        .alert("上传并使用 AI 识别", isPresented: $showUploadConsent) {
            Button("取消", role: .cancel) {}
            Button("同意并上传") { Task { await upload() } }
        } message: {
            Text("选中的试卷图片及备注将上传到学习服务器，图片会交给 DeepSeek AI 服务识别。原图、识别结果与题库记录会保存用于复习。请先遮住姓名、学校等个人信息，并确认有权上传。可在「右上角账号与设置 → 账号与隐私 → 注销账号」申请删除相关资料，需核验的申请通常 30 天内完成。")
        }
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
                if imgs.count != items.count { banner = "部分照片未能读取，请重新从相册选择。" }
                picked = []
            }
        }
    }

    private var thisYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }
    private var pending: Int { pages.filter { !$0.state.isUploaded }.count }
    private var hasBad: Bool { pages.contains { $0.state.isBad } }
    private var pagesTitle: String {
        pending > 0 ? "待传 \(pending) 页" : "这 \(pages.count) 页"
    }
    private var busyLabel: String {
        for p in pages {
            if case .reading(let sec) = p.state { return "第 \(p.page) 页读图中… \(sec)s" }
        }
        return "正在传…"
    }

    @ViewBuilder private func statusIcon(_ st: ScanPage.State) -> some View {
        switch st {
        case .idle:      EmptyView()
        case .uploading, .reading: ProgressView()
        case .uploaded:  Image(systemName: "arrow.up.circle").foregroundStyle(Ink.dim)
        case .done:      Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green)
        case .failed, .readFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Ink.red)
        }
    }

    private func statusLine(_ st: ScanPage.State) -> String? {
        switch st {
        case .idle, .uploading:        return nil
        case .uploaded(let job):       return job == nil ? "已存档，没派上自动读图" : "已传上，排队读图…"
        case .reading(let sec):        return "服务端读图中… \(sec)s"
        case .done(let s):             return s
        case .failed(let m):           return "没传上去：\(m)"
        case .readFailed(let m):       return "传上了，读图没成：\(m)"
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

    /// 逐页传，传完逐页等读图结果。**已经传成功的不重传** —— 中途断网重按一次只补没传上去的那几页，
    /// 而不是把服务端上已有的页再覆盖一遍（覆盖本身是允许的，只是白烧流量、白烧一次读图）。
    @MainActor
    private func upload() async {
        guard !busy else { return }
        let account: PaperRequestSession
        do { account = try PaperRequestSession.capture() }
        catch {
            banner = error.localizedDescription
            return
        }
        busy = true
        banner = nil
        defer { busy = false }

        // 同一页码传两次 = 后一张把前一张覆盖掉，而且**不会有任何报错**。
        // 传之前就拦住，比传完发现少一页强。
        let nums = pages.map(\.page)
        if Set(nums).count != nums.count {
            banner = "有两张标了同一个页码 —— 先改掉再传"
            return
        }

        for idx in pages.indices where !pages[idx].state.isUploaded {
            do { try account.requireCurrent() }
            catch { stopAfterAccountChange(); return }
            pages[idx].state = .uploading
            guard let d = PaperScan.jpeg(pages[idx].image) else {
                // 压不下去不是「传失败」，是这张图本身太满 —— 说清楚该怎么办。
                pages[idx].state = .failed("压不到 3MB 以内")
                continue
            }
            do {
                let r = try await Api.paperPage(slug: slug.text, page: pages[idx].page,
                                                jpeg: d, note: note, account: account)
                if let job = r.job {
                    pages[idx].state = .uploaded(job: job)
                } else {
                    let message = r.autoErr ?? "图片已存档，但未能创建识别任务，请联系支持。"
                    pages[idx].state = .readFailed(message)
                    pages[idx].log = message
                }
            } catch is PaperRequestSession.Changed {
                stopAfterAccountChange()
                return
            } catch {
                pages[idx].state = .failed(error.localizedDescription)
            }
            do { try account.requireCurrent() }
            catch { stopAfterAccountChange(); return }
        }
        do {
            try account.requireCurrent()
            try await readAll(account: account)
            try account.requireCurrent()
            await sync.sync(force: true, account: account)
            try account.requireCurrent()
        } catch {
            stopAfterAccountChange()
            return
        }

        // 汇总只摘服务端算好的数（每页那句「录进题库 N 道」），不自己数题。
        let got = pages.compactMap(\.got).reduce(0, +)
        let skipped = pages.compactMap(\.skipped).reduce(0, +)
        let bad: [String] = pages.compactMap { p in
            switch p.state {
            case .failed(let m):     return "p\(p.page) 没传上：\(m)"
            case .readFailed(let m): return "p\(p.page) 读图没成：\(m)"
            default:                 return nil
            }
        }
        var s = "录进题库 \(got) 道" + (skipped > 0 ? "，跳过 \(skipped) 道" : "")
        if !bad.isEmpty { s += "；" + bad.joined(separator: "；") }
        banner = (bad.isEmpty ? "✅ " : "") + s
    }

    private func stopAfterAccountChange() {
        for idx in pages.indices {
            switch pages[idx].state {
            case .idle, .uploading:
                pages[idx].state = .failed("账号已变化，本页未发送。请回到原账号后重新导入。")
            case .uploaded, .reading:
                pages[idx].state = .readFailed("图片已上传到原账号；已停止获取结果，请回到原账号核对。")
            default:
                break
            }
        }
        banner = "账号已变化，已停止本批次。剩余页面请回原账号重新选择；已上传的图片可在原账号核对。"
    }

    /// 一页一页等读图结果。服务端读图是串行的（同时派只会互相等锁），所以这边也顺着来。
    @MainActor private func readAll(account: PaperRequestSession) async throws {
        for idx in pages.indices {
            try account.requireCurrent()
            guard case .uploaded(let job?) = pages[idx].state else { continue }
            var sec = 0
            let deadline = Date().addingTimeInterval(15 * 60)
            pages[idx].state = .reading(0)
            poll: while true {
                try account.requireCurrent()
                guard !Task.isCancelled, Date() < deadline else {
                    pages[idx].state = .readFailed("等待识别结果超时，图片已保存。请稍后同步课程或联系支持。")
                    break
                }
                do {
                    let result = try await Api.job(job, account: account)
                    try account.requireCurrent()
                    switch result {
                    case .running:
                        try? await Task.sleep(for: .seconds(3)); sec += 3
                        pages[idx].state = .reading(sec)
                    case .done(let ok, let log):
                        pages[idx].log = log.trimmingCharacters(in: .whitespacesAndNewlines)
                        let (g, k) = Self.counts(in: log)
                        pages[idx].got = g; pages[idx].skipped = k
                        pages[idx].state = ok ? .done(Self.summary(log, got: g, skipped: k))
                                              : .readFailed(String(log.suffix(120)))
                        break poll
                    }
                } catch is PaperRequestSession.Changed {
                    throw PaperRequestSession.Changed()
                } catch {
                    if let failure = error as? Api.Failure,
                       [401, 403, 404, 410].contains(failure.statusCode) {
                        pages[idx].state = .readFailed(failure.localizedDescription)
                        break poll
                    }
                    // 网络抖一下不算失败 —— 作业在服务端照跑，等会儿再问
                    try? await Task.sleep(for: .seconds(5)); sec += 5
                    pages[idx].state = .reading(sec)
                }
            }
        }
    }

    /// 从 `wrong_ingest.py auto` 的输出里摘数。**只摘不数**：那两句是服务端算的。
    static func counts(in log: String) -> (got: Int?, skipped: Int?) {
        func n(_ re: Regex<(Substring, Substring)>) -> Int? {
            log.firstMatch(of: re).flatMap { Int($0.1) }
        }
        let got = n(/录进题库\s*(\d+)\s*道/)
        let skipped = n(/跳过\s*(\d+)\s*道/)
        if got == nil && log.contains("没读到做错的题") { return (0, 0) }
        return (got, skipped)
    }

    static func summary(_ log: String, got: Int?, skipped: Int?) -> String {
        if log.contains("没读到做错的题") { return "这页没读到错题（没有红叉/涂改的一律不收）" }
        guard let got else { return "跑完了，详情见读图记录" }
        var s = "录进题库 \(got) 道"
        if let skipped, skipped > 0 { s += "，跳过 \(skipped) 道" }
        if let m = log.firstMatch(of: /其中\s*(\d+)\s*道归不到现有的课/) { s += "（\(m.1) 道进了待归类）" }
        return s
    }
}
