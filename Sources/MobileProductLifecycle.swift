import Foundation
import CoreFoundation
#if os(macOS)
import AppKit
#endif

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    static let storeID = "6806626967"
    static let portableKeys = ["remind_enabled", "remind_hour", "appShortcuts.refresh.enabled", "appShortcuts.refresh.binding"]
    nonisolated static func validatePreference(_ key: String, _ value: Any) throws {
        switch key {
        case "remind_hour":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.intValue), (1...23).contains(number.intValue) else { throw AppUpdateError("提醒时间须为 1–23 时，原配置已保留。") }
        case "remind_enabled", "appShortcuts.refresh.enabled":
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AppUpdateError("开关须为布尔值，原配置已保留。") }
        case "appShortcuts.refresh.binding":
            guard let binding = value as? [String: Any], let key = binding["key"] as? String,
                  let flags = binding["modifiers"] as? NSNumber else { throw AppUpdateError("快捷键格式不正确。") }
            #if os(macOS)
            try AppShortcuts.validate(.init(key: key, modifiers: NSEvent.ModifierFlags(rawValue: flags.uintValue)))
            #else
            guard key.count == 1, flags.uintValue > 0 else { throw AppUpdateError("快捷键格式不正确。") }
            #endif
        default: throw AppUpdateError("此字段不属于可迁移配置。")
        }
    }
    static let preferences: UserDefaults = {
        #if DEBUG && (os(macOS) || os(iOS))
        let env = ProcessInfo.processInfo.environment
        if ProductBasicsSelfTest.requested {
            guard env["APP_LIFECYCLE_SUPPORT_DIR"] != nil,
                  let suite = env["WRONGBOOK_BASICS_DEFAULTS"], suite.hasPrefix("wrongbook.basics.") else {
                preconditionFailure("自检必须使用独立偏好域")
            }
            return UserDefaults(suiteName: suite)!
        }
        #endif
        return .standard
    }()
    /// Mac 版读 iCloud Drive 私有发行记录的渠道名；面板与命令（AppCommand）用同一个。
    static let macChannel = "private"
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        return .sandboxCloud(channel: macChannel)
        #else
        return .appStore(id: storeID)
        #endif
    }
    static let configuration: AppConfiguration? = {
        let configuration = AppConfiguration(productID: "wrong-book-mobile", defaultsKeys: portableKeys, defaults: preferences, validateDefault: validatePreference)
        if ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil {
            configuration.onChange = { Task { @MainActor in
                #if os(macOS)
                ProductSettings.shortcuts.refresh()
                #endif
                _ = await Reminder.reschedule(ask: false)
            } }
        }
        return configuration
    }()
}
