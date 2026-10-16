import Foundation
import OSLog

/// Opt-in, non-sensitive checkpoints for a real App process in the isolated lane.
/// Never emits an account identifier, token, address, request body or password.
enum StartupDiagnostics {
    static func mark(_ checkpoint: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "startup_diagnostics") else { return }
        Logger(subsystem: "cyou.tianli.wrongbook", category: "startup")
            .notice("checkpoint=\(checkpoint, privacy: .public)")
        #endif
    }
}
