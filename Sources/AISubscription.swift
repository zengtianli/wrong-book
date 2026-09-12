import StoreKit
import Combine
import Foundation
import OSLog

@MainActor
final class AISubscription: ObservableObject {
    static let shared = AISubscription()
    static let productIDs = ["cyou.tianli.wrongbook.monthly", "cyou.tianli.wrongbook.yearly"]
    @Published private(set) var access: Api.AIAccess?
    @Published private(set) var products: [Product] = []
    @Published private(set) var refreshingAccess = false
    @Published private(set) var processingPurchase = false
    @Published private(set) var loadingProducts = false
    @Published private(set) var productMessage: String?
    var busy: Bool { refreshingAccess || processingPurchase }
    @Published var message: String?
    @Published var purchaseIntent: Product?
    private let fetchProducts: () async throws -> [Product]
    private let fetchAccess: (PaperRequestSession) async throws -> Api.AIAccess
    private let syncPurchases: () async throws -> Void
    private let retryPause: (UInt64) async throws -> Void
    private var catalogTask: Task<Void, Never>?
    private var catalogGeneration = UUID()
    private var accountGeneration = UUID()
    private static let logger = Logger(subsystem: "cyou.tianli.wrongbook", category: "subscription")

    init(fetchProducts: @escaping () async throws -> [Product] = {
        try await Product.products(for: AISubscription.productIDs)
    }, fetchAccess: @escaping (PaperRequestSession) async throws -> Api.AIAccess = {
        try await Api.aiAccess(account: $0)
    }, syncPurchases: @escaping () async throws -> Void = {
        try await AppStore.sync()
    }, retryPause: @escaping (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }) {
        self.fetchProducts = fetchProducts
        self.fetchAccess = fetchAccess
        self.syncPurchases = syncPurchases
        self.retryPause = retryPause
    }

    func clearAccess() {
        access = nil
        message = nil
        accountGeneration = UUID()
        refreshingAccess = false
    }

    func listenForStorefrontChanges() async {
        for await _ in Storefront.updates {
            storefrontDidChange()
        }
    }

    func storefrontDidChange() {
        // Do not wait here: another storefront update must cancel this request too.
        catalogTask?.cancel()
        catalogTask = nil
        catalogGeneration = UUID()
        products = []
        _ = startCatalogLoad()
    }

    func loadProducts() async {
        await startCatalogLoad().value
    }

    private func startCatalogLoad() -> Task<Void, Never> {
        if let catalogTask { return catalogTask }
        let generation = UUID()
        catalogGeneration = generation
        loadingProducts = true
        productMessage = nil
        let task = Task { @MainActor in
            defer {
                if catalogGeneration == generation {
                    loadingProducts = false
                    catalogTask = nil
                }
            }
            do {
                let loaded = try await SubscriptionCatalog.load(
                    ids: Self.productIDs, identify: { $0.id }, fetch: fetchProducts, pause: retryPause)
                try Task.checkCancellation()
                guard catalogGeneration == generation else { return }
                products = loaded
                if loaded.count != Self.productIDs.count {
                    productMessage = loaded.isEmpty
                        ? "App Store 暂未返回订阅方案，请稍后重试。已有免费额度仍可使用。"
                        : "部分订阅方案暂不可用，可选择已显示的方案或重试。"
                }
                let storefront = await Storefront.current
                let missing = Self.productIDs.filter { id in !loaded.contains { $0.id == id } }
                Self.logger.info("Catalog storefront=\(storefront?.countryCode ?? "unknown", privacy: .public) missing=\(missing.joined(separator: ","), privacy: .public)")
            } catch is CancellationError {
                // A storefront change starts a replacement request.
            } catch {
                guard catalogGeneration == generation else { return }
                productMessage = "无法连接 App Store 获取订阅方案，请检查网络后重试。"
                let nsError = error as NSError
                Self.logger.error("Catalog failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            }
        }
        catalogTask = task
        return task
    }

    func listenForPurchaseIntents() async {
        for await intent in PurchaseIntent.intents where Self.productIDs.contains(intent.product.id) {
            purchaseIntent = intent.product
        }
    }

    func listen() async {
        for await result in Transaction.updates {
            let generation = accountGeneration
            do {
                let account = try PaperRequestSession.capture()
                try await accept(result, account: account, generation: generation)
            } catch {
                // Keep the transaction unfinished for login/retry/restore.
                if generation == accountGeneration { message = subscriptionError(error) }
            }
        }
    }

    private func accept(_ result: VerificationResult<Transaction>, account: PaperRequestSession, generation: UUID) async throws {
        guard generation == accountGeneration else { throw CancellationError() }
        guard case .verified(let tx) = result else {
            throw Api.Failure(message: "Apple 购买验证未通过，请恢复购买重试。")
        }
        guard Self.productIDs.contains(tx.productID) else { return }
        let current = try await fetchAccess(account)
        try account.requireCurrent()
        guard generation == accountGeneration else { throw CancellationError() }
        guard current.token != nil, tx.appAccountToken == nil || tx.appAccountToken == current.token else {
            throw Api.Failure(message: "这笔订阅属于另一个错题本账号，请登录购买时的账号后恢复购买。")
        }
        let updated = try await Api.appleTransaction(result.jwsRepresentation, account: account)
        try account.requireCurrent()
        guard generation == accountGeneration else { throw CancellationError() }
        access = updated
        await tx.finish()
    }

    func refresh() async {
        // The catalog does not depend on our login server or transaction delivery.
        async let catalog: Void = loadProducts()
        if !busy { await refreshAccess() }
        await catalog
    }

    private func subscriptionError(_ error: Error) -> String {
        if error is PaperRequestSession.Changed {
            return "登录状态已改变，请登录后重新同步订阅。"
        }
        return error.localizedDescription
    }

    private func refreshAccess(account suppliedAccount: PaperRequestSession? = nil) async {
        guard !refreshingAccess else { return }
        let generation = accountGeneration
        refreshingAccess = true
        access = nil
        message = nil
        defer { if generation == accountGeneration { refreshingAccess = false } }
        do {
            let account = try suppliedAccount ?? PaperRequestSession.capture()
            try account.requireCurrent()
            let current = try await fetchAccess(account)
            try account.requireCurrent()
            guard generation == accountGeneration else { return }
            access = current
            for await result in Transaction.currentEntitlements {
                if case .verified(let tx) = result, Self.productIDs.contains(tx.productID),
                   (tx.appAccountToken == nil || tx.appAccountToken == current.token) {
                    try await accept(result, account: account, generation: generation)
                }
            }
        } catch is CancellationError {
        } catch {
            if generation == accountGeneration { message = subscriptionError(error) }
        }
    }

    func purchase(_ product: Product) async {
        guard !busy else { return }
        guard Self.productIDs.contains(product.id) else { return }
        let generation = accountGeneration
        processingPurchase = true
        message = nil
        defer { processingPurchase = false }
        do {
            let account = try PaperRequestSession.capture()
            let current = try await fetchAccess(account)
            try account.requireCurrent()
            guard let token = current.token else { throw Api.Failure(message: "请先登录并同步账号。") }
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result):
                try await accept(result, account: account, generation: generation)
            case .pending:
                if generation == accountGeneration { message = "购买等待 Apple 确认；确认后会自动更新权益。" }
            case .userCancelled:
                break
            @unknown default:
                if generation == accountGeneration { message = "购买状态尚未确认，请稍后恢复购买。" }
            }
        } catch {
            if generation == accountGeneration { message = subscriptionError(error) }
        }
    }

    func restore() async {
        guard !busy else { return }
        let generation = accountGeneration
        processingPurchase = true
        message = nil
        defer { processingPurchase = false }
        do {
            let account = try PaperRequestSession.capture()
            try await syncPurchases()
            try account.requireCurrent()
            guard generation == accountGeneration else { return }
            await refreshAccess(account: account)
            if generation == accountGeneration, access?.subscribed != true, message == nil {
                message = "当前错题本账号没有有效订阅。请确认 Apple 账户与购买时的错题本账号。"
            }
        } catch {
            if generation == accountGeneration { message = subscriptionError(error) }
        }
    }
}
