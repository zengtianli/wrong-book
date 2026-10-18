// Product controls only; configuration transfer and release checking stay in Shared/.
import SwiftUI
import CoreFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
enum ProductSettings {
    private static let lifecycle = MobileLifecycleModel(productID: "wrong-book", channel: MobileProductLifecycle.channel,
                                                       configuration: MobileProductLifecycle.configuration)
    static func model() -> MobileLifecycleModel {
        lifecycle
    }
    #if os(macOS)
    static weak var activeController: ProductSettingsController?
    static let shortcuts = AppShortcuts(defaults: MobileProductLifecycle.preferences) {
        if let activeController { activeController.check() } else { model().checkForUpdates() }
        Task { await LessonSync.shared.sync(force: true) }
    }
    static func installShortcuts() { shortcuts.installMenu(); shortcuts.menuItem?.title = String(localized: "同步错题并检查更新"); shortcuts.refresh() }
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: ProductSettingsPanel(model: model(), close: { window?.close() }))
            let w = NSWindow(contentViewController: controller); w.title = String(localized: "错题本 · 设置"); w.isReleasedWhenClosed = false; window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
    #endif
    static func validateImport(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["values"] as? [String: Any] else { throw AppUpdateError("配置格式不正确，原配置已保留。") }
        for (key, value) in values {
            guard key.hasPrefix("defaults.") else { throw AppUpdateError("此字段不属于可迁移配置。") }
            try MobileProductLifecycle.validatePreference(String(key.dropFirst("defaults.".count)), value)
        }
        #if os(macOS)
        if let binding = values["defaults.appShortcuts.refresh.binding"] {
            guard let value = binding as? [String: Any], let key = value["key"] as? String,
                  let flags = value["modifiers"] as? NSNumber else { throw AppUpdateError("快捷键格式不正确。") }
            let candidate = AppShortcuts.Binding(key: key, modifiers: NSEvent.ModifierFlags(rawValue: flags.uintValue))
            try AppShortcuts.validate(candidate)
            guard !shortcuts.conflicts(candidate) else { throw AppUpdateError("快捷键与本 App 菜单冲突，原配置已保留。") }
        }
        #endif
    }
}

// Keep the established entry label/placement, including the compact login screen.
struct ProductSettingsEntry: View {
    @StateObject private var model = ProductSettings.model()
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label(String(localized: "配置与更新"), systemImage: "gearshape") }
            .accessibilityIdentifier("app.configurationAndUpdates")
            .sheet(isPresented: $showing) {
                #if os(macOS) || os(iOS)
                if model.configuration != nil { ProductSettingsPanel(model: model) }
                else { AppLifecycleMobilePanel(model: model) }
                #else
                AppLifecycleMobilePanel(model: model)
                #endif
            }
    }
}

#if os(macOS) || os(iOS)
struct ProductSettingsPanel: View {
    let model: MobileLifecycleModel
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var selecting = false
    @State private var document = AppConfigurationDocument()
    @State private var notice: String?
    var body: some View {
        VStack {
            ProductSettingsRepresentable(model: model, export: {
                do { document = AppConfigurationDocument(data: try model.configuration!.exportData()); exporting = true }
                catch { notice = Api.displayError(error) }
            }, import: { importing = true }, select: { selecting = true })
            Button(String(localized: "完成")) { if let close { close() } else { dismiss() } }.padding(.bottom)
        }
        .frame(minWidth: 340, idealWidth: 520, minHeight: 560)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "wrong-book-config") { result in
            if case .failure(let error) = result { notice = Api.displayError(error) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                try ProductSettings.validateImport(data); try model.configuration!.importData(data); model.refreshConfiguration()
            } catch { notice = Api.displayError(error) }
        }
        #if os(macOS)
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.folder]) { result in
            do { model.selectUpdateDirectory(try result.get()) } catch { notice = Api.displayError(error) }
        }
        #endif
        .alert(String(localized: "配置与更新"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(String(localized: "好")) { notice = nil }
        } message: { Text(notice ?? "") }
    }
}

#if os(macOS)
struct ProductSettingsRepresentable: NSViewControllerRepresentable {
    let model: MobileLifecycleModel
    var export: () -> Void; var `import`: () -> Void; var select: () -> Void
    func makeNSViewController(context: Context) -> ProductSettingsController {
        let ui = ProductSettingsController(model: model); ui.exportAction = export; ui.importAction = self.import; ui.selectAction = select; return ui
    }
    func updateNSViewController(_ ui: ProductSettingsController, context: Context) {}
}

private final class ProductSettingsSurface: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}

final class ProductSettingsController: NSViewController {
    let model: MobileLifecycleModel
    let reminder = NSButton(checkboxWithTitle: String(localized: "每日提醒"), target: nil, action: nil)
    let hour = NSPopUpButton(frame: .zero, pullsDown: false)
    let cloud = NSButton(checkboxWithTitle: String(localized: "使用 iCloud 记住配置"), target: nil, action: nil)
    let shortcut = NSButton(checkboxWithTitle: String(localized: "启用同步错题并检查更新快捷键"), target: nil, action: nil)
    let binding = NSPopUpButton(frame: .zero, pullsDown: false)
    let checkUpdate = NSButton(title: String(localized: "检查更新"), target: nil, action: nil)
    let storeEntry = NSButton(title: String(localized: "打开发行包"), target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "")
    var exportAction: () -> Void = {}; var importAction: () -> Void = {}; var selectAction: () -> Void = {}
    var openUpdate: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    private var observations: [NSObjectProtocol] = []
    init(model: MobileLifecycleModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        ProductSettings.activeController = self
        view = ProductSettingsSurface(frame: NSRect(x: 0, y: 0, width: 520, height: 650))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)])
        func label(_ text: String) { stack.addArrangedSubview(NSTextField(wrappingLabelWithString: text)) }
        func button(_ title: String, _ action: Selector) { let b = NSButton(title: title, target: self, action: action); stack.addArrangedSubview(b) }
        label(String(localized: "错题本 · 配置与更新  \(model.version) (\(model.build))"))
        hour.addItems(withTitles: (1...23).map { "\($0):00" }); binding.addItems(withTitles: ["⌘R", "⇧⌘R"])
        for (control, action) in [(reminder as NSControl, #selector(saveReminder)), (hour, #selector(saveReminder)), (cloud, #selector(toggleCloud)), (shortcut, #selector(toggleShortcut)), (binding, #selector(changeBinding)), (checkUpdate, #selector(check)), (storeEntry, #selector(open))] {
            control.target = self; control.action = action
        }
        [reminder, hour, cloud, shortcut, binding].forEach { stack.addArrangedSubview($0) }
        label(String(localized: "快捷键仅在本 App 中生效；⌘Q/W/H/M 及编辑键保留。关闭后仍可点同步按钮。"))
        button(String(localized: "导出配置…"), #selector(exportConfig)); button(String(localized: "导入配置…"), #selector(importConfig))
        button(String(localized: "选择 iCloud Drive 更新目录…"), #selector(selectDirectory))
        stack.addArrangedSubview(checkUpdate); stack.addArrangedSubview(storeEntry); stack.addArrangedSubview(status)
        label(String(localized: "iCloud 默认关闭，仅同步提醒与快捷键；账号、学习资料、目录授权不随配置迁移。解开已校验的发行 ZIP 后手动替换 App，保留数据。"))
        model.start(); refresh()
        observations.append(NotificationCenter.default.addObserver(forName: Notification.Name("AppConfigurationStatusChanged"), object: model.configuration, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observations.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
    }
    @objc func saveReminder() {
        // Capture both controls before defaults notifications refresh this view.
        let enabled = reminder.state == .on, selectedHour = hour.indexOfSelectedItem + 1
        MobileProductLifecycle.preferences.set(enabled, forKey: "remind_enabled"); MobileProductLifecycle.preferences.set(selectedHour, forKey: "remind_hour"); saved()
    }
    @objc func toggleCloud() { model.setCloudEnabled(cloud.state == .on); refresh() }
    @objc func toggleShortcut() { ProductSettings.shortcuts.setEnabled(shortcut.state == .on); refresh() }
    @objc func changeBinding() {
        do { try ProductSettings.shortcuts.setBinding(.init(key: "r", modifiers: binding.indexOfSelectedItem == 0 ? .command : [.command, .shift])) }
        catch { model.notice = Api.displayError(error) }; refresh()
    }
    @objc func check() { model.checkForUpdates(); Task { while model.checking { try? await Task.sleep(for: .milliseconds(50)) }; refresh() } }
    @objc func open() {
        model.openSandboxPackage(using: OpenURLAction { url in self.openUpdate(url) ? .handled : .discarded })
    }
    @objc func exportConfig() { exportAction() }
    @objc func importConfig() { importAction() }
    @objc func selectDirectory() { selectAction() }
    func importData(_ data: Data) throws { try ProductSettings.validateImport(data); try model.configuration!.importData(data); refresh() }
    private func saved() { MobileProductLifecycle.preferences.synchronize(); if ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil { Task { _ = await Reminder.reschedule(ask: false) } }; refresh() }
    func refresh() {
        model.refreshConfiguration(); reminder.state = MobileProductLifecycle.preferences.bool(forKey: "remind_enabled") ? .on : .off
        let h = MobileProductLifecycle.preferences.integer(forKey: "remind_hour"); hour.selectItem(at: (1...23).contains(h) ? h - 1 : 18)
        cloud.state = model.cloudEnabled ? .on : .off; shortcut.state = ProductSettings.shortcuts.enabled ? .on : .off
        binding.selectItem(at: ProductSettings.shortcuts.binding.modifiers.contains(.shift) ? 1 : 0)
        checkUpdate.isEnabled = !model.checking; storeEntry.isEnabled = model.updateURL != nil
        status.stringValue = model.configurationStatus + "\n" + model.updateStatus + (model.notice.map { "\n" + $0 } ?? "")
    }
}
#else
struct ProductSettingsRepresentable: UIViewControllerRepresentable {
    let model: MobileLifecycleModel
    var export: () -> Void; var `import`: () -> Void; var select: () -> Void
    func makeUIViewController(context: Context) -> ProductSettingsController {
        let ui = ProductSettingsController(model: model); ui.exportAction = export; ui.importAction = self.import; return ui
    }
    func updateUIViewController(_ ui: ProductSettingsController, context: Context) {}
}
final class ProductSettingsController: UIViewController {
    let model: MobileLifecycleModel
    let reminder = UISwitch(); let hour = UIStepper(); let hourLabel = UILabel()
    let cloud = UISwitch(); let checkUpdate = UIButton(type: .system); let storeEntry = UIButton(type: .system)
    let status = UILabel()
    var exportAction: () -> Void = {}; var importAction: () -> Void = {}
    var openUpdate: ((URL) -> Void)?
    private var observations: [NSObjectProtocol] = []
    init(model: MobileLifecycleModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14; stack.alignment = .fill
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)])
        func label(_ text: String) { let l = UILabel(); l.text = text; l.numberOfLines = 0; stack.addArrangedSubview(l) }
        func button(_ title: String, _ action: Selector) { let b = UIButton(type: .system); b.setTitle(title, for: .normal); b.addTarget(self, action: action, for: .touchUpInside); stack.addArrangedSubview(b) }
        label(String(localized: "错题本 · 配置与更新  \(model.version) (\(model.build))"))
        label(String(localized: "每日提醒")); stack.addArrangedSubview(reminder)
        hour.minimumValue = 1; hour.maximumValue = 23; hour.stepValue = 1
        let hourRow = UIStackView(arrangedSubviews: [hourLabel, hour]); hourRow.distribution = .equalSpacing; stack.addArrangedSubview(hourRow)
        reminder.addTarget(self, action: #selector(saveReminder), for: .valueChanged); hour.addTarget(self, action: #selector(saveReminder), for: .valueChanged)
        label(String(localized: "使用 iCloud 记住配置")); stack.addArrangedSubview(cloud); cloud.addTarget(self, action: #selector(toggleCloud), for: .valueChanged)
        label(String(localized: "默认关闭；仅同步提醒与 Mac 快捷键。账号、错题、登录态与权限不在配置中。"))
        button(String(localized: "导出配置…"), #selector(exportConfig)); button(String(localized: "导入配置…"), #selector(importConfig))
        checkUpdate.setTitle(String(localized: "检查更新"), for: .normal); checkUpdate.addTarget(self, action: #selector(check), for: .touchUpInside); stack.addArrangedSubview(checkUpdate)
        storeEntry.setTitle(String(localized: "前往 App Store"), for: .normal); storeEntry.addTarget(self, action: #selector(open), for: .touchUpInside); stack.addArrangedSubview(storeEntry)
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .footnote); stack.addArrangedSubview(status)
        model.start(); refresh()
        observations.append(NotificationCenter.default.addObserver(forName: Notification.Name("AppConfigurationStatusChanged"), object: model.configuration, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observations.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
    }
    @objc func saveReminder() {
        let enabled = reminder.isOn, selectedHour = Int(hour.value)
        MobileProductLifecycle.preferences.set(enabled, forKey: "remind_enabled"); MobileProductLifecycle.preferences.set(selectedHour, forKey: "remind_hour"); MobileProductLifecycle.preferences.synchronize(); if ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil { Task { _ = await Reminder.reschedule(ask: false) } }; refresh()
    }
    @objc func toggleCloud() { model.setCloudEnabled(cloud.isOn); refresh() }
    @objc func check() { model.checkForUpdates(); Task { while model.checking { try? await Task.sleep(for: .milliseconds(50)) }; refresh() } }
    @objc func open() {
        guard let url = model.updateURL else { return }
        if let openUpdate { openUpdate(url); return }
        UIApplication.shared.open(url) { [weak self] accepted in
            guard !accepted else { return }
            Task { @MainActor in self?.model.notice = String(localized: "系统未能打开 App Store，请从系统商店搜索错题本。"); self?.refresh() }
        }
    }
    @objc func exportConfig() { exportAction() }
    @objc func importConfig() { importAction() }
    func importData(_ data: Data) throws { try ProductSettings.validateImport(data); try model.configuration!.importData(data); refresh() }
    func refresh() {
        model.refreshConfiguration(); reminder.isOn = MobileProductLifecycle.preferences.bool(forKey: "remind_enabled")
        let h = MobileProductLifecycle.preferences.integer(forKey: "remind_hour"); hour.value = Double((1...23).contains(h) ? h : 19); hourLabel.text = String(localized: "每天 \(Int(hour.value)):00")
        cloud.isOn = model.cloudEnabled; checkUpdate.isEnabled = !model.checking
        status.text = model.configurationStatus + "\n" + model.updateStatus + (model.notice.map { "\n" + $0 } ?? "")
    }
}
#endif
#endif
