import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    /// Mac 版读 iCloud Drive 私有发行记录的渠道名；面板与命令（AppCommand）用同一个。
    static let macChannel = "private"
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        return .sandboxCloud(channel: macChannel)
        #else
        return .appStore(id: "6806626967")
        #endif
    }
    static let configuration: AppConfiguration? = {
        let configuration = AppConfiguration(productID: "wrong-book-mobile", defaultsKeys: ["remind_enabled", "remind_hour"])
        configuration.onChange = { Task { @MainActor in _ = await Reminder.reschedule(ask: false) } }
        return configuration
    }()
}
