#if DEBUG && (os(macOS) || os(iOS))
import SwiftUI
import CryptoKit
import ObjectiveC

#if os(iOS)
// Only an isolated DEBUG process forwards the shared HTTPS lookup to a real loopback fixture.
private extension URLSessionConfiguration {
    @objc class func wrongbookAcceptance() -> URLSessionConfiguration {
        let configuration = wrongbookAcceptance()
        configuration.protocolClasses = [ProductBasicsTransport.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}
final class ProductBasicsTransport: URLProtocol {
    private var forwardingTask: URLSessionDataTask?
    override class func canInit(with request: URLRequest) -> Bool {
        ProductBasicsSelfTest.requested && ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] != nil && request.url?.host == "itunes.apple.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let source = request.url, let base = ProcessInfo.processInfo.environment["WRONGBOOK_BASICS_SERVER"],
              let url = URL(string: base + source.path + "?" + (source.query ?? "")), url.host == "127.0.0.1" else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        forwardingTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
            guard let response = response as? HTTPURLResponse, let data,
                  let forwarded = HTTPURLResponse(url: source, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
            self.client?.urlProtocol(self, didReceive: forwarded, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
        }; forwardingTask?.resume()
    }
    override func stopLoading() { forwardingTask?.cancel() }
}
// Adopt the real scene lifecycle (required by iOS 27); only the fixture scene starts,
// never the normal Session, account views or business tasks.
struct ProductBasicsApp: App {
    var body: some Scene {
        WindowGroup { Color.clear.task { await ProductBasicsSelfTest.run() } }
    }
}
#endif

@MainActor
enum ProductBasicsSelfTest {
    nonisolated static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--ui-self-test") }
    static func reconcile(_ configuration: AppConfiguration) async -> Error? {
        await withCheckedContinuation { continuation in configuration.reconcile { continuation.resume(returning: $0) } }
    }
    static func waitUpdate(_ model: MobileLifecycleModel) async {
        for _ in 0..<450 { if !model.checking { return }; try? await Task.sleep(for: .milliseconds(50)) }
    }
    static func write(_ value: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic) }
    static func values(_ configuration: AppConfiguration) throws -> [String: Any] { try JSONSerialization.jsonObject(with: configuration.exportData()) as! [String: Any] }
    static func run() async {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["WRONGBOOK_BASICS_OUTPUT"], let cloudRoot = env["APP_LIFECYCLE_CLOUD_DIR"],
              env["APP_LIFECYCLE_SUPPORT_DIR"] != nil, let digest = env["WRONGBOOK_BASICS_DIGEST"],
              env["WRONGBOOK_BASICS_DEFAULTS"]?.hasPrefix("wrongbook.basics.") == true else { exit(2) }
        let phase = env["WRONGBOOK_BASICS_PHASE"] ?? "exercise"
        let preferences = MobileProductLifecycle.preferences, configuration = MobileProductLifecycle.configuration!
        let model = ProductSettings.model(), ui = ProductSettingsController(model: model)
        var checks: [String: Bool] = [:], facts: [String: Any] = [:]
        #if os(macOS)
        _ = ui.view; ui.view.frame = NSRect(x: 0, y: 0, width: 560, height: 650)
        NSApp.mainMenu = NSMenu(); ProductSettings.installShortcuts()
        func clickCloud(_ on: Bool) { ui.cloud.state = on ? .on : .off; _ = ui.cloud.sendAction(ui.cloud.action, to: ui.cloud.target) }
        func saveHour(_ hour: Int) { ui.reminder.state = .on; ui.hour.selectItem(at: hour - 1); _ = ui.hour.sendAction(ui.hour.action, to: ui.hour.target) }
        func clickCheck() { ui.checkUpdate.performClick(nil) }
        #else
        ui.loadViewIfNeeded(); ui.view.frame = CGRect(x: 0, y: 0, width: 390, height: 900); ui.view.layoutIfNeeded()
        func clickCloud(_ on: Bool) { ui.cloud.isOn = on; ui.cloud.sendActions(for: .valueChanged) }
        func saveHour(_ hour: Int) { ui.reminder.isOn = true; ui.hour.value = Double(hour); ui.hour.sendActions(for: .valueChanged) }
        func clickCheck() { ui.checkUpdate.sendActions(for: .touchUpInside) }
        #endif
        let cloudFile = URL(fileURLWithPath: cloudRoot).appendingPathComponent("wrong-book-mobile.json")
        do {
            if phase == "readback" {
                checks["settings.persisted_readback"] = preferences.integer(forKey: "remind_hour") == 7 && preferences.bool(forKey: "remind_enabled") && !configuration.enabled
                #if os(macOS)
                checks["settings.controls_readback"] = ui.hour.indexOfSelectedItem == 6 && ui.reminder.state == .on
                checks["shortcuts.persisted_readback"] = ProductSettings.shortcuts.enabled && ProductSettings.shortcuts.binding.modifiers == [.command, .shift]
                #else
                checks["settings.controls_readback"] = ui.hour.value == 7 && ui.reminder.isOn
                #endif
            } else {
                saveHour(7)
                checks["settings.interaction"] = preferences.integer(forKey: "remind_hour") == 7 && preferences.bool(forKey: "remind_enabled") && ui.view.window == nil
                let saved = try configuration.exportData(); saveHour(21); try ui.importData(saved)
                checks["settings.export_import"] = preferences.integer(forKey: "remind_hour") == 7
                let beforeBad = try configuration.exportData()
                var rejected = false
                do { try ui.importData(Data("{\"version\":1,\"product\":\"wrong-book-mobile\",\"values\":{\"defaults.remind_hour\":99}}".utf8)) } catch { rejected = true }
                let afterBad = try configuration.exportData()
                checks["settings.error_preserves_data"] = rejected && afterBad == beforeBad
                let envelope = try values(configuration), exported = envelope["values"] as! [String: Any]
                checks["settings.credentials_excluded"] = Set(exported.keys).isSubset(of: Set(MobileProductLifecycle.portableKeys.map { "defaults." + $0 }))
                // The actual UI toggle drives the shared configuration engine, then another device envelope is received.
                clickCloud(true); let pushedError = await reconcile(configuration)
                var remote = try JSONSerialization.jsonObject(with: Data(contentsOf: cloudFile)) as! [String: Any]
                var remoteValues = remote["values"] as! [String: Any]
                let pushedHour = remoteValues["defaults.remind_hour"] as? Int
                remoteValues["defaults.remind_hour"] = 21; remote["values"] = remoteValues
                try write(remote, cloudFile); let pullError = await reconcile(configuration); ui.refresh()
                checks["icloud.push_pull"] = pushedError == nil && pushedHour == 7 && pullError == nil && preferences.integer(forKey: "remind_hour") == 21
                let offlineBefore = try configuration.exportData()
                unsetenv("APP_LIFECYCLE_CLOUD_DIR"); let offlineError = await reconcile(configuration); setenv("APP_LIFECYCLE_CLOUD_DIR", cloudRoot, 1)
                ui.refresh()
                let afterOffline = try configuration.exportData()
                checks["icloud.unavailable_local_fallback"] = offlineError != nil && afterOffline == offlineBefore && preferences.integer(forKey: "remind_hour") == 21
                let goodCloud = try Data(contentsOf: cloudFile); try Data("{broken".utf8).write(to: cloudFile, options: .atomic)
                let badCloud = await reconcile(configuration), preserved = try configuration.exportData() == offlineBefore
                try goodCloud.write(to: cloudFile, options: .atomic); let recovered = await reconcile(configuration)
                checks["icloud.conflict_or_corrupt_recovery"] = badCloud != nil && preserved && recovered == nil
                let beforeDisable = try configuration.exportData(), cloudBeforeDisable = try Data(contentsOf: cloudFile)
                clickCloud(false); _ = await reconcile(configuration)
                let afterDisable = try configuration.exportData(), cloudAfterDisable = try Data(contentsOf: cloudFile)
                checks["icloud.disable_preserves_data"] = !configuration.enabled && afterDisable == beforeDisable && cloudAfterDisable == cloudBeforeDisable
                #if os(macOS)
                let feed = URL(fileURLWithPath: cloudRoot).appendingPathComponent("TianliApps/Updates/\(model.bundleID)/private/release.json")
                try FileManager.default.createDirectory(at: feed.deletingLastPathComponent(), withIntermediateDirectories: true)
                let package = feed.deletingLastPathComponent().appendingPathComponent("fixture.zip")
                let packageData = try Data(contentsOf: URL(fileURLWithPath: env["WRONGBOOK_BASICS_PACKAGE"]!)); try packageData.write(to: package)
                let release: [String: Any] = ["bundle_id": model.bundleID, "version": "99.0", "build": "1", "channel": "private", "installation": "manual-bundle", "filename": package.lastPathComponent, "size_bytes": packageData.count, "sha256": SHA256.hash(data: packageData).map { String(format: "%02x", $0) }.joined()]
                clickCheck(); await waitUpdate(model)
                let missing = model.release == nil && model.updateStatus.contains("检查未完成")
                try Data("{broken".utf8).write(to: feed); clickCheck(); await waitUpdate(model)
                let corrupt = model.release == nil && !model.checking
                try write(release, feed); clickCheck(); await waitUpdate(model); ui.refresh()
                checks["updates.failure_recovery"] = missing && corrupt && model.release?.version == "99.0" && ui.checkUpdate.isEnabled
                var opened: URL?; ui.openUpdate = { opened = $0; return true }; ui.storeEntry.performClick(nil)
                for _ in 0..<100 { if opened != nil { break }; try? await Task.sleep(for: .milliseconds(50)) }
                checks["updates.options_or_store_entry"] = opened == package && ui.storeEntry.isEnabled
                // Actual shared menu target/action, no key events. Update checking is an observable action result.
                model.release = nil
                if let item = ProductSettings.shortcuts.menuItem { _ = NSApp.sendAction(item.action!, to: item.target, from: item) }
                await waitUpdate(model)
                for _ in 0..<20 { if ui.status.stringValue.contains("99.0") { break }; try? await Task.sleep(for: .milliseconds(50)) }
                checks["shortcuts.action_path"] = model.release?.version == "99.0" && ui.status.stringValue.contains("99.0") && ProductSettings.shortcuts.menuItem?.keyEquivalent == "r"
                ui.shortcut.state = .off; _ = ui.shortcut.sendAction(ui.shortcut.action, to: ui.shortcut.target)
                let disabled = !ProductSettings.shortcuts.enabled && ProductSettings.shortcuts.menuItem?.keyEquivalent == ""
                ui.shortcut.state = .on; _ = ui.shortcut.sendAction(ui.shortcut.action, to: ui.shortcut.target)
                ui.binding.selectItem(at: 1); _ = ui.binding.sendAction(ui.binding.action, to: ui.binding.target)
                checks["shortcuts.disable_restore"] = disabled && ProductSettings.shortcuts.enabled && ProductSettings.shortcuts.menuItem?.keyEquivalent == "r" && ProductSettings.shortcuts.binding.modifiers == [.command, .shift]
                let previous = ProductSettings.shortcuts.binding.dictionary as NSDictionary
                var reserved = false, conflict = false
                do { try ProductSettings.shortcuts.setBinding(.init(key: "q", modifiers: .command)) } catch { reserved = true }
                let other = NSMenuItem(title: "另一操作", action: nil, keyEquivalent: "t"); other.keyEquivalentModifierMask = .command; NSApp.mainMenu?.addItem(other)
                do { try ProductSettings.shortcuts.setBinding(.init(key: "t", modifiers: .command)) } catch { conflict = true }
                checks["shortcuts.conflict_or_reserved_keys"] = reserved && conflict && previous == ProductSettings.shortcuts.binding.dictionary as NSDictionary
                checks["settings.offscreen"] = NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow } && ui.view.window == nil
                #else
                guard let original = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral)), let isolated = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.wrongbookAcceptance)) else { throw AppUpdateError("隔离更新传输不可用") }
                method_exchangeImplementations(original, isolated); defer { method_exchangeImplementations(original, isolated) }
                func mode(_ name: String) async throws { _ = try await URLSession.shared.data(from: URL(string: env["WRONGBOOK_BASICS_SERVER"]! + "/mode/" + name)!) }
                try await mode("new"); clickCheck(); await waitUpdate(model); ui.refresh()
                var opened: URL?; ui.openUpdate = { opened = $0 }; ui.storeEntry.sendActions(for: .touchUpInside)
                checks["updates.options_or_store_entry"] = opened?.host == "apps.apple.com" && opened?.path.contains(MobileProductLifecycle.storeID) == true
                try await mode("unavailable"); clickCheck(); await waitUpdate(model)
                let unavailable = model.release == nil && model.updateStatus.contains("503")
                try await mode("corrupt"); clickCheck(); await waitUpdate(model)
                let corrupt = model.release == nil && model.updateStatus.contains("检查未完成")
                try await mode("new"); clickCheck(); await waitUpdate(model); ui.refresh()
                checks["updates.failure_recovery"] = unavailable && corrupt && model.release?.version == "99.0" && ui.checkUpdate.isEnabled
                checks["settings.offscreen"] = ui.view.window == nil && ui.presentedViewController == nil
                #endif
                checks["updates.check_result"] = model.release?.version == "99.0" && !model.checking
                let cloudAfterUpdate = try Data(contentsOf: cloudFile)
                checks["updates.data_preservation"] = preferences.integer(forKey: "remind_hour") == 21 && cloudAfterUpdate == cloudBeforeDisable && !configuration.enabled
                saveHour(7)
            }
            ui.refresh()
            let screenshot = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("settings-\(phase).png")
            #if os(macOS)
            let window = NSWindow(contentRect: ui.view.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentViewController = ui; window.appearance = NSAppearance(named: .aqua)
            window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            ui.view.layoutSubtreeIfNeeded(); let bitmap = ui.view.bitmapImageRepForCachingDisplay(in: ui.view.bounds)!
            ui.view.cacheDisplay(in: ui.view.bounds, to: bitmap); try bitmap.representation(using: .png, properties: [:])!.write(to: screenshot)
            checks["settings.controls_in_bounds"] = [ui.hour, ui.cloud, ui.checkUpdate, ui.storeEntry, ui.status].allSatisfy { ui.view.bounds.contains($0.convert($0.bounds, to: ui.view)) }
            let hidden = !window.isVisible && !window.isKeyWindow
            window.performClose(nil)
            checks["settings.close_action"] = hidden && !window.isVisible && !window.isKeyWindow && NSApp.activationPolicy() == .prohibited
            #else
            ui.view.layoutIfNeeded(); let image = UIGraphicsImageRenderer(size: ui.view.bounds.size).image { ui.view.layer.render(in: $0.cgContext) }; try image.pngData()!.write(to: screenshot)
            #endif
            facts["screenshot"] = screenshot.lastPathComponent; facts["configuration_status"] = model.configurationStatus; facts["update_status"] = model.updateStatus
            facts["remind_hour"] = preferences.integer(forKey: "remind_hour")
        } catch { checks["settings.completed"] = false; facts["error"] = error.localizedDescription }
        let raw: [String: Any] = ["schema_version": 1, "app_id": "wrong-book-ios", "spec_digest": digest, "phase": phase,
            "pid": ProcessInfo.processInfo.processIdentifier, "version": model.version, "build": model.build, "checks": checks, "facts": facts,
            "scope": "真实产品内原生离屏控件及共享配置/更新/快捷键路径；独立偏好域与云目录；iOS 真实本地 HTTP 更新源；苹果跨设备传输未验。"]
        try? write(raw, URL(fileURLWithPath: output))
        exit(!checks.isEmpty && checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}
#endif
