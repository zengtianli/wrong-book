import Foundation
import Security

/// 手表 App → 表盘复杂功能的那份复习摘要，存在手表本机钥匙串里（两个手表 target 同一个 access group，
/// 见 Watch.entitlements / WatchWidget.entitlements；不传 kSecAttrAccessGroup = 落在第一项）。
///
/// 只有手表 App 写：每次刷新成功写一次，iPhone 退出登录时删掉。复杂功能只读，不联网 ——
/// 一条常驻的网络请求会让手表的无线一直醒着。为什么是钥匙串不是 App Group：钥匙串组不需要
/// 在开发者后台另外登记，同一团队前缀就能共享（与成长小金库同一做法）。
enum DigestSnapshot {
    private static let service = "cyou.tianli.wrongbook.review"
    private static let account = "current"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// 写一份；nil = 删掉（退出登录后表盘不再显示上一个账号的错题）。
    @discardableResult
    static func save(_ digest: ReviewDigest?) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard let digest, let data = try? JSONEncoder().encode(digest) else { return digest == nil }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> ReviewDigest? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ReviewDigest.self, from: data)
    }
}
