import Foundation
import SwiftUI
import WebKit

/// 登录态。**只有登录态** —— 这个 app 的其它状态都在 WebView 里（练习引擎的存档）
/// 或在盘上（下载来的课页），原生不再复制一份。
@MainActor
final class Session: ObservableObject {
    enum Phase { case checking, loggedOut, loggedIn }

    @Published var phase: Phase = .checking
    @Published var status: Status?
    @Published var error: String?
    @Published var busy = false
    @Published var deletionReceipt: DeletionReceipt?
    @Published var deletionNotice: String?
    @Published var deletionRefreshError: String?
    private let receiptKey = "accountDeletionReceipt"

    init() {
        if let data = UserDefaults.standard.data(forKey: receiptKey) {
            deletionReceipt = try? JSONDecoder().decode(DeletionReceipt.self, from: data)
        }
    }

    private func saveReceipt(_ receipt: DeletionReceipt) {
        deletionReceipt = receipt
        if let data = try? JSONEncoder().encode(receipt) {
            UserDefaults.standard.set(data, forKey: receiptKey)
        }
    }

    private func finishLocalDeletion(scope: String?) async {
        let deletedStore = scope.map { LessonPaths.webDataStore(scope: $0) }
        LessonSync.shared.setUser(nil)
        status = nil
        phase = .loggedOut
        EduArchive.shared.resetAfterAccountDeletion()
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains(Api.base.host ?? "edu.tianli.cyou") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        if let deletedStore {
            await deletedStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        do {
            if let scope { try LessonPaths.removeFiles(scope: scope) }
            deletionNotice = "账号注销已完成，当前账号的本机课程副本、网页存档及登录信息已清除。"
        } catch {
            deletionNotice = "账号注销已完成，但本机课程副本清理失败。资料已停用，请联系支持协助清理。"
        }
    }

    func refreshDeletion() async {
        deletionRefreshError = nil
        do {
            if deletionReceipt == nil, let user = status?.user, var receipt = try await Api.currentDeletion() {
                receipt.owner = user
                receipt.scope = LessonSync.shared.scopeForCurrentUser(user)
                saveReceipt(receipt)
            }
            guard let old = deletionReceipt, old.status == "pending" else { return }
            var latest = try await Api.deletionProgress(receiptID: old.id)
            latest.owner = old.owner
            latest.scope = old.scope
            saveReceipt(latest)
            if latest.status == "completed" {
                let currentScope = LessonPaths.activeScope
                if (old.scope != nil && currentScope == old.scope) || (status == nil && currentScope == nil) {
                    await finishLocalDeletion(scope: old.scope)
                }
                else {
                    do {
                        if let scope = old.scope {
                            await LessonPaths.webDataStore(scope: scope).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                            try LessonPaths.removeFiles(scope: scope)
                        }
                        deletionNotice = "此前提交的账号注销申请已完成，当前登录账号不受影响。"
                    } catch { deletionNotice = "此前账号注销已完成，本机旧副本清理失败，请联系支持。" }
                }
            }
        } catch {
            // Keep the durable receipt; a network error never means deletion succeeded.
            if deletionReceipt?.status == "pending" {
                deletionRefreshError = "暂时无法刷新注销进度：" + error.localizedDescription
            }
        }
    }

    /// 开屏先探一次：cookie 还在就直接进，不必再问一次密码。
    ///
    /// 探不到**不等于**密码错了 —— 也可能是没网。所以一律落到登录页，
    /// 那里能重试也能显示原因。⚠ 超时给 6s 而不是 20s：这次请求挡在任何界面之前，
    /// 没网时用户要盯着转圈等满 20 秒 —— 那是「app 坏了」的观感。
    ///
    /// 注意：**没登录照样能做题**。页面是自包含的，登录只决定分记不记得上、
    /// 存档同不同步。所以登录页上有一条「先不登录，直接做题」。
    func restore() async {
        // 验证通道：只有显式传了 launch 参数才生效，生产路径上这两个 key 永远是 nil
        let d = UserDefaults.standard
        if let u = d.string(forKey: "dev_user"), let pw = d.string(forKey: "dev_pw") {
            await login(user: u, password: pw)
            return
        }
        do {
            status = try await Api.status(timeout: 6)
            LessonSync.shared.setUser(status?.user)
            phase = .loggedIn
        } catch {
            // An explicit authentication rejection never unlocks a cached account.
            if error is URLError, LessonSync.shared.restoreOffline() {
                status = nil
                phase = .loggedIn
            } else {
                LessonSync.shared.setUser(nil)
                phase = .loggedOut
            }
        }
    }

    func login(user: String, password: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.login(user: user, password: password)
            status = try await Api.status()
            LessonSync.shared.setUser(status?.user)
            phase = .loggedIn
        } catch {
            self.error = error.localizedDescription
            // ⚠ 必须落回 loggedOut：从 restore() 的 dev 分支进来时 phase 还是 .checking，
            // 不落回就永远停在开屏转圈上 —— 界面不动，也没有任何错误可看。
            phase = .loggedOut
        }
    }

    func register(email: String, password: String, nick: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.register(email: email, password: password, nick: nick)
            status = try await Api.status()
            LessonSync.shared.setUser(status?.user)
            phase = .loggedIn
        } catch {
            self.error = error.localizedDescription        // 邮箱已注册 / 格式不对 / 名额满，服务端文案原样
        }
    }

    /// true 表示删除完成或申请已受理；deletionReceipt/notice 区分这两种结果。
    func deleteAccount(password: String) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do {
            let scope = status.flatMap { LessonSync.shared.scopeForCurrentUser($0.user) }
            try await Api.deleteAccount(password: password)
            await finishLocalDeletion(scope: scope)
            return true
        } catch let failure as Api.Failure where failure.statusCode == 409 {
            do {
                var receipt = try await Api.requestAccountDeletion(password: password)
                receipt.owner = status?.user ?? ""
                receipt.scope = LessonSync.shared.scopeForCurrentUser(receipt.owner)
                saveReceipt(receipt)
                deletionNotice = "注销申请已受理，尚未完成删除。通常 30 天内完成；处理期间暂停新增数据。可在「我的」查看进度，超时请联系支持。"
                return true
            } catch {
                self.error = error.localizedDescription
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard phase == .loggedIn else { return }
        if let s = try? await Api.status() {
            let reconnecting = LessonPaths.offlineReadOnly
            status = s
            LessonSync.shared.setUser(s.user)
            if reconnecting { await LessonSync.shared.sync(force: true) }
        }
    }

    func logout() async {
        await Api.logout()
        LessonSync.shared.setUser(nil)
        status = nil
        phase = .loggedOut
    }

    /// Guest preview has no personal courses or historic storage.
    func skipLogin() { LessonSync.shared.setUser(nil); status = nil; phase = .loggedIn }
}
