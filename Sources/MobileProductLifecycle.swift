import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        return .sandboxCloud(channel: "private")
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
