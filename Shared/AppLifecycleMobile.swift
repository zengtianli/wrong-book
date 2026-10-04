// Shared source: Dev/tools/dev/lib/tools/macapp/swift-shared/AppLifecycleMobile.swift.
// Consumers vendor this file byte-for-byte; configuration and update rules stay in the shared core.
#if !os(watchOS)
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS) && APP_LIFECYCLE_KVS
import CryptoKit
#endif

enum MobileUpdateChannel {
    case appStore(id: String)
    case testFlight
    case privateCloud(channel: String)
    case unreleased(helpURL: URL?, instructions: String)
    #if os(macOS) && APP_LIFECYCLE_KVS
    case sandboxCloud(channel: String)
    #endif

    var name: String {
        switch self {
        case .appStore: return "App Store"
        case .testFlight: return "TestFlight"
        case .privateCloud: return "iCloud 私有发行包"
        case .unreleased: return "本地构建"
        #if os(macOS) && APP_LIFECYCLE_KVS
        case .sandboxCloud: return "iCloud 私有发行包"
        #endif
        }
    }
}

@MainActor
final class MobileLifecycleModel: ObservableObject {
    let productID: String
    let channel: MobileUpdateChannel
    let configuration: AppConfiguration?
    let version: String
    let build: String
    let bundleID: String
    @Published var cloudEnabled = false
    @Published var configurationStatus = ""
    @Published var updateStatus = "尚未检查"
    @Published var checking = false
    @Published var release: AppRelease?
    @Published var notice: String?
    private var started = false

    init(productID: String, channel: MobileUpdateChannel, configuration: AppConfiguration?) {
        self.productID = productID
        self.channel = channel
        // Existing demo/acceptance launch arguments must never start production configuration sync.
        var fixtureArguments: Set<String> = ["-demo", "--guide-demo", "-lane_demo", "-lane_quiet", "-lane_state",
                                             "-folio-demo", "-daily-review-demo"]
        #if DEBUG
        fixtureArguments.formUnion(["-dev_user", "-api_base", "-fitcoach.baseURL", "-relayBase", "-gatepw"])
        #endif
        self.configuration = ProcessInfo.processInfo.arguments.contains(where: fixtureArguments.contains) ? nil : configuration
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未标明"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未标明"
        bundleID = Bundle.main.bundleIdentifier ?? ""
        switch channel {
        case .appStore: break
        case .privateCloud: break
        case .testFlight: updateStatus = "内测版本由 TestFlight 检查并安装更新。"
        case .unreleased(_, let instructions): updateStatus = instructions
        #if os(macOS) && APP_LIFECYCLE_KVS
        case .sandboxCloud: updateStatus = "首次使用请选择 iCloud Drive 更新目录。"
        #endif
        }
    }

    func start() {
        guard !started else { return }
        started = true
        if let configuration {
            configuration.start()
            refreshConfiguration()
        }
    }

    func refreshConfiguration() {
        cloudEnabled = configuration?.enabled ?? false
        configurationStatus = configuration?.status ?? "本 App 没有可迁移的偏好配置。"
    }

    func setCloudEnabled(_ enabled: Bool) {
        configuration?.setEnabled(enabled)
        refreshConfiguration()
    }

    func checkForUpdates() {
        guard !checking else { return }
        #if os(macOS) && APP_LIFECYCLE_KVS
        if case .sandboxCloud(let channel) = channel {
            checking = true
            updateStatus = "正在检查…"
            MacSandboxUpdateAccess.check(bundleID: bundleID, channel: channel) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.checking = false
                    switch result {
                    case .success(let release):
                        self.release = release
                        self.updateStatus = release.isNewer(than: self.version, build: self.build)
                            ? "发现新版本 \(release.version) (\(release.build))。"
                            : "当前版本 \(self.version) (\(self.build))；发行版本 \(release.version) (\(release.build))。"
                    case .failure(let error):
                        self.release = nil
                        self.updateStatus = "检查未完成：\(error.localizedDescription)"
                    }
                }
            }
            return
        }
        #endif
        let source: AppUpdateSource
        switch channel {
        case .appStore(let id): source = .appStore(id: id)
        case .privateCloud(let channel): source = .privateCloud(channel: channel)
        default: return
        }
        checking = true
        updateStatus = "正在检查…"
        AppUpdateChecker.check(source: source, bundleID: bundleID, version: version, build: build) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.checking = false
                switch result {
                case .success(let release):
                    self.release = release
                    self.updateStatus = release.isNewer(than: self.version, build: self.build)
                        ? "发现新版本 \(release.version) (\(release.build))。"
                        : "当前版本 \(self.version) (\(self.build))；发行版本 \(release.version) (\(release.build))。"
                case .failure(let error):
                    self.release = nil
                    self.updateStatus = "检查未完成：\(error.localizedDescription)"
                }
            }
        }
    }

    var updateURL: URL? {
        switch channel {
        case .appStore(let id): return release?.releaseURL ?? URL(string: "https://apps.apple.com/app/id\(id)")
        case .testFlight: return URL(string: "itms-beta://")
        case .privateCloud: return release?.downloadURL ?? release?.releaseURL
        case .unreleased(let url, _): return url
        #if os(macOS) && APP_LIFECYCLE_KVS
        case .sandboxCloud: return release?.downloadURL
        #endif
        }
    }

    #if os(macOS) && APP_LIFECYCLE_KVS
    func selectUpdateDirectory(_ url: URL) {
        do {
            try MacSandboxUpdateAccess.selectDirectory(url)
            release = nil
            checkForUpdates()
        } catch { notice = "目录授权未完成：\(error.localizedDescription)" }
    }

    func openSandboxPackage(using openURL: OpenURLAction) {
        guard case .sandboxCloud(let channel) = channel, let release else { return }
        MacSandboxUpdateAccess.openPackage(release, bundleID: bundleID, channel: channel,
            open: { url, finished in Task { @MainActor in openURL(url, completion: finished) } }) { [weak self] result in
            Task { @MainActor in
                if case .failure(let error) = result { self?.notice = "发行包未打开：\(error.localizedDescription)" }
            }
        }
    }
    #endif
}

#if os(macOS) && APP_LIFECYCLE_KVS
// Sandbox access only. Feed validation and version comparison remain in AppUpdateChecker.
// This bookmark is a machine permission: it is deliberately outside every configuration allowlist.
enum MacSandboxUpdateAccess {
    private static let bookmarkKey = "AppLifecycle.local.privateUpdateDirectoryBookmark"

    private final class Access {
        let root: URL
        let scoped: Bool
        init(root: URL, scoped: Bool) { self.root = root; self.scoped = scoped }
        deinit { if scoped { root.stopAccessingSecurityScopedResource() } }
    }

    static func selectDirectory(_ url: URL) throws {
        guard ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil else {
            throw AppUpdateError("隔离运行只使用显式测试更新目录。")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              FileManager.default.isUbiquitousItem(at: url) else {
            throw AppUpdateError("请选择系统 iCloud Drive 根目录。")
        }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    private static func access() throws -> Access {
        let environment = ProcessInfo.processInfo.environment
        if environment["APP_LIFECYCLE_SUPPORT_DIR"] != nil {
            guard let cloud = environment["APP_LIFECYCLE_CLOUD_DIR"], !cloud.isEmpty else {
                throw AppUpdateError("隔离运行没有配置测试更新目录。")
            }
            return Access(root: URL(fileURLWithPath: cloud), scoped: false)
        }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw AppUpdateError("请先选择 iCloud Drive 更新目录，授予此 Mac 读取发行包的权限。")
        }
        var stale = false
        let root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard root.startAccessingSecurityScopedResource() else {
            throw AppUpdateError("更新目录权限已失效，请重新选择 iCloud Drive 更新目录。")
        }
        let access = Access(root: root, scoped: true)
        guard FileManager.default.isUbiquitousItem(at: root) else {
            throw AppUpdateError("所选 iCloud Drive 目录暂不可用，请检查系统 iCloud Drive 状态。")
        }
        if stale {
            let refreshed = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                 includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return access
    }

    private static func feed(in root: URL, bundleID: String, channel: String) throws -> URL {
        let components = [bundleID, channel]
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.count < 240 &&
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }) else {
            throw AppUpdateError("无效的更新渠道。")
        }
        let file = root.appendingPathComponent("TianliApps/Updates/\(bundleID)/\(channel)/release.json")
        let prefix = root.resolvingSymlinksInPath().path + "/"
        guard file.resolvingSymlinksInPath().path.hasPrefix(prefix) else {
            throw AppUpdateError("发行目录超出所选 iCloud Drive 目录。")
        }
        return file
    }

    private static func coordinated<T>(_ url: URL, read: (URL) throws -> T) throws -> T {
        if FileManager.default.isUbiquitousItem(at: url) { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
        var error: NSError?, result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { resolved in
            result = Result { try read(resolved) }
        }
        if let error { throw error }
        guard let result else { throw AppUpdateError("无法读取 iCloud 发行记录。") }
        return try result.get()
    }

    static func check(bundleID: String, channel: String, completion: @escaping (Result<AppRelease, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(Result {
                let access = try access()
                defer { withExtendedLifetime(access) {} }
                let file = try feed(in: access.root, bundleID: bundleID, channel: channel)
                return try coordinated(file) { url in
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes > 0 && bytes <= AppUpdateChecker.maximumFeedSize else {
                        throw AppUpdateError("发行记录为空或过大。")
                    }
                    let release = try AppUpdateChecker.manifest(Data(contentsOf: url), at: file,
                                                               bundleID: bundleID, channel: channel)
                    guard release.installation == "manual-bundle", release.downloadURL?.pathExtension.lowercased() == "zip",
                          (release.size ?? 0) > 0 else {
                        throw AppUpdateError("此 Mac 沙盒版需要手动安装的正式 ZIP 发行包。")
                    }
                    return release
                }
            })
        }
    }

    static func openPackage(_ release: AppRelease, bundleID: String, channel: String,
                            open: @escaping (URL, @escaping (Bool) -> Void) -> Void,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let access = try access()
                let file = try feed(in: access.root, bundleID: bundleID, channel: channel)
                guard release.installation == "manual-bundle", release.bundleID == bundleID, release.channel == channel,
                      let package = release.downloadURL, package.isFileURL, package.pathExtension.lowercased() == "zip",
                      package.deletingLastPathComponent().resolvingSymlinksInPath() == file.deletingLastPathComponent().resolvingSymlinksInPath(),
                      let expectedHash = release.sha256, let expectedSize = release.size, expectedSize > 0 else {
                    throw AppUpdateError("发行包身份或路径不匹配，请重新检查更新。")
                }
                try coordinated(package) { url in
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          Int64(values.fileSize ?? 0) == expectedSize, let stream = InputStream(url: url) else {
                        throw AppUpdateError("发行包尚未完整下载，请稍后重试。")
                    }
                    stream.open()
                    defer { stream.close() }
                    var hasher = SHA256(), buffer = [UInt8](repeating: 0, count: 65_536)
                    while true {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count >= 0 else { throw stream.streamError ?? AppUpdateError("无法读取发行包。") }
                        if count == 0 { break }
                        hasher.update(data: Data(buffer.prefix(count)))
                    }
                    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    guard hash.lowercased() == expectedHash.lowercased() else { throw AppUpdateError("发行包校验失败，请重新下载。") }
                }
                open(package) { accepted in
                    withExtendedLifetime(access) {}
                    completion(accepted ? .success(()) : .failure(AppUpdateError("系统未能打开 ZIP 发行包。")))
                }
            } catch { completion(.failure(error)) }
        }
    }
}
#endif

struct AppConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct AppLifecycleMobilePanel: View {
    @ObservedObject var model: MobileLifecycleModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var exporting = false
    @State private var document = AppConfigurationDocument()
    #if os(macOS) && APP_LIFECYCLE_KVS
    @State private var selectingUpdateDirectory = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("应用版本") {
                    LabeledContent("已安装", value: "\(model.version) (\(model.build))")
                    LabeledContent("更新渠道", value: model.channel.name)
                    Text(model.updateStatus).font(.footnote).foregroundStyle(.secondary)
                    updateControls
                }
                Section("配置") {
                    if let configuration = model.configuration, configuration.hasSettings {
                        Toggle("使用 iCloud 记住配置", isOn: Binding(get: { model.cloudEnabled }, set: model.setCloudEnabled))
                            .accessibilityIdentifier("configuration.iCloud")
                        Text(model.configurationStatus).font(.footnote).foregroundStyle(.secondary)
                        Text("跟随系统 Apple 账户；默认关闭。开启后只同步本 App 的偏好配置，关闭后保留本机设置。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("导出配置…") {
                            do { document = AppConfigurationDocument(data: try configuration.exportData()); exporting = true }
                            catch { model.notice = error.localizedDescription }
                        }.accessibilityIdentifier("configuration.export")
                        Button("导入配置…") { importing = true }.accessibilityIdentifier("configuration.import")
                    } else {
                        Text("本 App 没有可迁移的偏好配置。内容同步与登录仍使用原有入口。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("配置与更新")
            .toolbar { ToolbarItem { Button("完成") { dismiss() } } }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 450)
            #endif
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "\(model.productID)-config") { result in
            switch result {
            case .success: model.notice = "配置已导出。"
            case .failure(let error): model.notice = "导出未完成：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first, let configuration = model.configuration else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                try configuration.importData(Data(contentsOf: url))
                model.refreshConfiguration()
                model.notice = "配置已导入。"
            } catch { model.notice = "导入未完成：\(error.localizedDescription)" }
        }
        .alert("配置与更新", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

    @ViewBuilder private var updateControls: some View {
        switch model.channel {
        case .appStore:
            Button(model.checking ? "正在检查…" : "检查更新") { model.checkForUpdates() }.disabled(model.checking)
                .accessibilityIdentifier("update.check")
            Button("前往 App Store") { openUpdateURL() }
        case .testFlight:
            Button("在 TestFlight 中检查更新") { openUpdateURL() }.accessibilityIdentifier("update.check")
        case .privateCloud:
            Button(model.checking ? "正在检查…" : "检查更新") { model.checkForUpdates() }.disabled(model.checking)
                .accessibilityIdentifier("update.check")
            if model.updateURL != nil { Button("打开发行包") { openUpdateURL() } }
        case .unreleased:
            if model.updateURL != nil { Button("打开安装说明") { openUpdateURL() }.accessibilityIdentifier("update.check") }
        #if os(macOS) && APP_LIFECYCLE_KVS
        case .sandboxCloud:
            Button("选择 iCloud Drive 更新目录…") { selectingUpdateDirectory = true }
                .accessibilityIdentifier("update.directory")
                .fileImporter(isPresented: $selectingUpdateDirectory, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        model.selectUpdateDirectory(url)
                    } catch { model.notice = "目录选择未完成：\(error.localizedDescription)" }
                }
            Text("首次选择系统 iCloud Drive 根目录；目录授权只保存在这台 Mac。检查后打开 ZIP，将其中的 App 放入应用程序文件夹完成升级。")
                .font(.footnote).foregroundStyle(.secondary)
            Button(model.checking ? "正在检查…" : "检查更新") { model.checkForUpdates() }.disabled(model.checking)
                .accessibilityIdentifier("update.check")
            if model.updateURL != nil { Button("打开发行包") { model.openSandboxPackage(using: openURL) } }
        #endif
        }
    }

    private func openUpdateURL() {
        guard let url = model.updateURL else { return }
        openURL(url) { accepted in
            if !accepted { model.notice = "系统未能打开更新入口。请从 App Store 或 TestFlight 打开本 App 的版本页面。" }
        }
    }
}

enum AppLifecycleMobilePlacement {
    case footer
    // The product puts AppLifecycleMobileEntry in its existing settings/login UI.
    case settings
}

struct AppLifecycleMobileEntry: View {
    @EnvironmentObject private var model: MobileLifecycleModel
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("配置与更新", systemImage: "gearshape") }
            .accessibilityIdentifier("app.configurationAndUpdates")
            .sheet(isPresented: $showing) { AppLifecycleMobilePanel(model: model) }
    }
}

private struct AppLifecycleMobileModifier: ViewModifier {
    @StateObject private var model: MobileLifecycleModel
    @State private var showing = false
    let placement: AppLifecycleMobilePlacement

    init(productID: String, channel: MobileUpdateChannel, configuration: AppConfiguration?, placement: AppLifecycleMobilePlacement) {
        _model = StateObject(wrappedValue: MobileLifecycleModel(productID: productID, channel: channel, configuration: configuration))
        self.placement = placement
    }

    @ViewBuilder private func placed(_ content: Content) -> some View {
        switch placement {
        case .footer:
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button { showing = true } label: { Label("配置与更新", systemImage: "gearshape") }
                        .accessibilityIdentifier("app.configurationAndUpdates")
                    Spacer()
                }.font(.footnote).padding(.vertical, 7).background(.bar)
            }
        case .settings:
            content
        }
    }

    func body(content: Content) -> some View {
        placed(content)
            .environmentObject(model)
            .task { model.start() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AppConfigurationStatusChanged"), object: model.configuration)) { _ in
                model.refreshConfiguration()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                model.refreshConfiguration()
            }
            .sheet(isPresented: $showing) { AppLifecycleMobilePanel(model: model) }
    }
}

extension View {
    func appLifecycleMobile(productID: String, channel: MobileUpdateChannel, configuration: AppConfiguration? = nil,
                            placement: AppLifecycleMobilePlacement = .footer) -> some View {
        modifier(AppLifecycleMobileModifier(productID: productID, channel: channel, configuration: configuration, placement: placement))
    }
}
#endif
