import StoreKit
import Combine
import Foundation

@MainActor
final class AISubscription: ObservableObject {
    static let shared = AISubscription()
    static let productIDs = ["cyou.tianli.wrongbook.monthly", "cyou.tianli.wrongbook.yearly"]
    @Published private(set) var access: Api.AIAccess?
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published var message: String?

    func clearAccess() {
        access = nil
        message = nil
    }

    func listen() async {
        for await result in Transaction.updates {
            do {
                let account = try PaperRequestSession.capture()
                try await accept(result, account: account)
            } catch {
                // Keep the transaction unfinished for login/retry/restore.
                message = error.localizedDescription
            }
        }
    }

    private func accept(_ result: VerificationResult<Transaction>, account: PaperRequestSession) async throws {
        guard case .verified(let tx) = result else {
            throw Api.Failure(message: "Apple 购买验证未通过，请恢复购买重试。")
        }
        guard Self.productIDs.contains(tx.productID) else { return }
        let current = try await Api.aiAccess(account: account)
        try account.requireCurrent()
        guard tx.appAccountToken == current.token, current.token != nil else {
            throw Api.Failure(message: "这笔订阅属于另一个错题本账号，请登录购买时的账号后恢复购买。")
        }
        let updated = try await Api.appleTransaction(result.jwsRepresentation, account: account)
        try account.requireCurrent()
        access = updated
        await tx.finish()
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        access = nil
        message = nil
        defer { busy = false }
        do {
            let account = try PaperRequestSession.capture()
            let current = try await Api.aiAccess(account: account)
            try account.requireCurrent()
            access = current
            for await result in Transaction.currentEntitlements {
                if case .verified(let tx) = result, Self.productIDs.contains(tx.productID),
                   tx.appAccountToken == current.token {
                    try await accept(result, account: account)
                }
            }
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            try account.requireCurrent()
            if products.count != Self.productIDs.count {
                message = "订阅产品暂不可用，请稍后重试。免费额度仍可正常使用。"
            }
        } catch { message = error.localizedDescription }
    }

    func purchase(_ product: Product) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let account = try PaperRequestSession.capture()
            let current = try await Api.aiAccess(account: account)
            try account.requireCurrent()
            guard let token = current.token else { throw Api.Failure(message: "请先登录并同步账号。") }
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result):
                try await accept(result, account: account)
            case .pending:
                message = "购买等待 Apple 确认；确认后会自动更新权益。"
            case .userCancelled:
                break
            @unknown default:
                message = "购买状态尚未确认，请稍后恢复购买。"
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        message = nil
        do { try await AppStore.sync() }
        catch { message = error.localizedDescription; busy = false; return }
        busy = false
        await refresh()
        if access?.subscribed != true, message == nil {
            message = "当前错题本账号没有有效订阅。请确认 Apple 账户与购买时的错题本账号。"
        }
    }
}
