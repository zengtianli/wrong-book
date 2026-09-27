import Foundation
import StoreKit

// Real production catalog/service/API/account binding; only library identity and
// external operations are injected. Successful StoreKit paths are intentionally
// excluded: they inspect Storefront/currentEntitlements even with fake products.
enum LessonPaths {
    static var offlineReadOnly = false
    static var activeScope: String?
}

@main
struct RecoveryAcceptance {
    enum Fault: Error { case unavailable }

    @MainActor static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Fixture did not reach its expected suspension point")
    }

    @MainActor static func main() async throws {
        let ids = ["monthly", "yearly"]
        var calls = 0
        var pauses: [UInt64] = []
        let recovered = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
            calls += 1
            if calls == 1 { throw Fault.unavailable }
            if calls == 2 { return ["monthly", "monthly"] }
            return ["yearly", "unrelated"]
        }, pause: { pauses.append($0) })
        precondition(recovered == ids && calls == 3)
        precondition(pauses == [500_000_000, 1_500_000_000], "Retry delay schedule changed")

        calls = 0
        let partial = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
            calls += 1
            if calls == 1 { return ["monthly"] }
            throw Fault.unavailable
        }, pause: { _ in })
        precondition(partial == ["monthly"] && calls == 3, "A later failure discarded a usable plan")

        calls = 0
        do {
            let _: [String] = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
                calls += 1
                throw Fault.unavailable
            }, pause: { _ in })
            preconditionFailure("Exhausted transport failures were hidden")
        } catch Fault.unavailable { precondition(calls == 3) }

        calls = 0
        do {
            let _: [String] = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
                calls += 1
                return []
            }, pause: { _ in throw CancellationError() })
            preconditionFailure("Cancellation resumed catalog work")
        } catch is CancellationError { precondition(calls == 1) }

        // Hold the first fetch until the second caller joins the same request.
        // Every product operation throws before production can inspect StoreKit.
        var productCalls = 0
        var productReply: CheckedContinuation<[Product], Error>?
        let catalog = AISubscription(fetchProducts: {
            productCalls += 1
            if productCalls == 1 {
                return try await withCheckedThrowingContinuation { productReply = $0 }
            }
            throw Fault.unavailable
        }, fetchAccess: { _ in throw Fault.unavailable }, syncPurchases: {
            throw Fault.unavailable
        }, retryPause: { _ in })
        let firstLoad = Task { await catalog.loadProducts() }
        await waitUntil { productReply != nil }
        var secondStarted = false
        let secondLoad = Task {
            secondStarted = true
            await catalog.loadProducts()
        }
        await waitUntil { secondStarted }
        productReply!.resume(throwing: Fault.unavailable)
        await firstLoad.value
        await secondLoad.value
        precondition(productCalls == 3, "Concurrent callers duplicated catalog requests")
        precondition(!catalog.loadingProducts && catalog.productMessage?.contains("无法连接") == true)
        await catalog.loadProducts()
        precondition(productCalls == 6 && !catalog.loadingProducts, "Failure left manual retry stuck")

        // Synthetic account state is volatile and scoped to this fixture's host.
        let origin = URL(string: "https://recovery-\(UUID().uuidString.lowercased()).invalid")!
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments["api_base"] = origin.absoluteString
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        LessonPaths.activeScope = "fixture-a"
        let cookie = HTTPCookie(properties: [
            .domain: origin.host!, .path: "/", .name: "edu_sess", .value: "synthetic-recovery"
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)
        defer {
            defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            HTTPCookieStorage.shared.deleteCookie(cookie)
            LessonPaths.activeScope = nil
        }

        var accessCalls = 0
        var independentCalls = 0
        let backend = AISubscription(fetchProducts: {
            independentCalls += 1
            throw Fault.unavailable
        }, fetchAccess: { _ in
            accessCalls += 1
            throw Api.Failure(message: "fixture backend failure \(accessCalls)")
        }, syncPurchases: { throw Fault.unavailable }, retryPause: { _ in })
        await backend.refresh()
        precondition(accessCalls == 1 && independentCalls == 3)
        precondition(backend.message == "fixture backend failure 1" && backend.access == nil)
        precondition(!backend.busy && !backend.loadingProducts)
        await backend.refresh()
        precondition(accessCalls == 2 && independentCalls == 6)
        precondition(backend.message == "fixture backend failure 2" && !backend.busy)

        var accessReply: CheckedContinuation<Api.AIAccess, Error>?
        let changingAccount = AISubscription(fetchProducts: { throw Fault.unavailable }, fetchAccess: { _ in
            try await withCheckedThrowingContinuation { accessReply = $0 }
        }, syncPurchases: { throw Fault.unavailable }, retryPause: { _ in })
        let oldRefresh = Task { await changingAccount.refresh() }
        await waitUntil { accessReply != nil }
        LessonPaths.activeScope = "fixture-b"
        changingAccount.clearAccess()
        accessReply!.resume(returning: Api.AIAccess(["enabled": true, "subscribed": true]))
        await oldRefresh.value
        precondition(changingAccount.access == nil && changingAccount.message == nil)
        precondition(!changingAccount.busy && !changingAccount.loadingProducts,
                     "An old account response restored stale state")

        var syncCalls = 0
        var restoreAccessCalls = 0
        let restore = AISubscription(fetchProducts: { throw Fault.unavailable }, fetchAccess: { _ in
            restoreAccessCalls += 1
            throw Fault.unavailable
        }, syncPurchases: {
            syncCalls += 1
            if syncCalls == 1 { throw Fault.unavailable }
            LessonPaths.activeScope = "fixture-c"
        }, retryPause: { _ in })
        await restore.restore()
        precondition(syncCalls == 1 && !restore.busy && restore.message != nil)
        await restore.restore()
        precondition(syncCalls == 2 && restoreAccessCalls == 0 && !restore.busy)
        precondition(restore.access == nil && restore.message?.contains("登录状态已改变") == true,
                     "Restore crossed into a different account")

        print("PASS: catalog fault-to-success/partial preservation/retry bounds/cancellation; subscription concurrent loads, error-state retry, backend independence, stale-account rejection and restore failure release")
    }
}
