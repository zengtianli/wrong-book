import Foundation

// Test-only persistence boundary for the existing identity/import regressions.
// Compile alongside the unchanged production Api, Session and PaperRequestSession.
// A command-line executable must never read or write the user's standard defaults.
// All keys are private to this process and disappear when it exits.
enum UserDefaults {
    static let standard = PrivacyAcceptanceDefaults()
}

final class PrivacyAcceptanceDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func removeObject(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }

    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
}
