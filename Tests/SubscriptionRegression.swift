import Foundation
import StoreKit

// Compile the production catalog, subscription service, API and account binding.
// No purchases or backend HTTP are used; only local library identity is replaced.
// xcrun --sdk macosx swiftc -target arm64-apple-macos15.0 Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift Sources/SubscriptionCatalog.swift Sources/AISubscription.swift Tests/SubscriptionRegression.swift -o /tmp/wrongbook-subscription-test
// /tmp/wrongbook-subscription-test
enum LessonPaths {
    static var offlineReadOnly = false
    static var activeScope: String?
}

@main struct SubscriptionRegression {
    enum Offline: Error { case unavailable }

    @MainActor static func main() async throws {
        let ids = ["monthly", "yearly"]
        var calls = 0
        var delays: [UInt64] = []
        let recovered = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
            calls += 1
            if calls == 1 { return [] }
            if calls == 2 { throw Offline.unavailable }
            return ["yearly", "monthly", "unrelated"]
        }, pause: { delays.append($0) })
        precondition(recovered == ids && calls == 3 && delays.count == 2)

        calls = 0
        let partial = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
            calls += 1
            if calls == 1 { return ["monthly", "monthly"] }
            throw Offline.unavailable
        }, pause: { _ in })
        precondition(partial == ["monthly"] && calls == 3, "A valid plan must survive later errors")

        calls = 0
        let empty: [String] = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
            calls += 1
            return []
        }, pause: { _ in })
        precondition(empty.isEmpty && calls == 3, "Empty catalog must stop retrying")

        calls = 0
        do {
            let _: [String] = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
                calls += 1
                throw Offline.unavailable
            }, pause: { _ in })
            fatalError("Network failure was hidden")
        } catch Offline.unavailable { precondition(calls == 3) }

        calls = 0
        do {
            let _: [String] = try await SubscriptionCatalog.load(ids: ids, identify: { $0 }, fetch: {
                calls += 1
                return []
            }, pause: { _ in throw CancellationError() })
            fatalError("Cancelled catalog returned a result")
        } catch is CancellationError { precondition(calls == 1) }

        // A failed login/account snapshot must not prevent StoreKit loading, and
        // overlapping screen/foreground refreshes must share the catalog request.
        var storeCalls = 0
        let store = AISubscription(fetchProducts: {
            storeCalls += 1
            await Task.yield()
            return []
        }, retryPause: { _ in await Task.yield() })
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        precondition(storeCalls == 3, "Concurrent refresh duplicated or skipped StoreKit work")
        precondition(store.message != nil && store.productMessage != nil)
        precondition(store.access == nil && !store.busy && !store.loadingProducts)
        store.clearAccess()
        precondition(store.message == nil && store.productMessage != nil)
        await store.loadProducts()
        precondition(storeCalls == 6 && !store.loadingProducts, "Manual retry remained stuck")

        let failingStore = AISubscription(fetchProducts: { throw Offline.unavailable }, retryPause: { _ in })
        await failingStore.refresh()
        precondition(failingStore.productMessage?.contains("无法连接") == true)
        precondition(!failingStore.busy && !failingStore.loadingProducts)

        // In-flight responses from a cancelled storefront cannot clear the new
        // request's error or loading state, even if StoreKit ignores cancellation.
        var oldCatalog: CheckedContinuation<[Product], Error>?
        var changeCalls = 0
        let changingStore = AISubscription(fetchProducts: {
            changeCalls += 1
            if changeCalls == 1 { return try await withCheckedThrowingContinuation { oldCatalog = $0 } }
            throw Offline.unavailable
        }, retryPause: { _ in })
        let oldLoad = Task { await changingStore.loadProducts() }
        while oldCatalog == nil { await Task.yield() }
        changingStore.storefrontDidChange()
        await changingStore.loadProducts()
        precondition(changeCalls == 4 && changingStore.productMessage?.contains("无法连接") == true)
        oldCatalog!.resume(returning: [])
        await oldLoad.value
        precondition(!changingStore.loadingProducts && changingStore.productMessage?.contains("无法连接") == true)

        let origin = URL(string: "https://wrongbook-subscription-fixture.invalid")!
        let defaults = UserDefaults.standard
        let oldBase = defaults.object(forKey: "api_base")
        defaults.set(origin.absoluteString, forKey: "api_base")
        LessonPaths.activeScope = "subscription-fixture-a"
        let cookie = HTTPCookie(properties: [.domain: origin.host!, .path: "/", .name: "edu_sess", .value: "synthetic-a"])!
        HTTPCookieStorage.shared.setCookie(cookie)
        defer {
            if let oldBase { defaults.set(oldBase, forKey: "api_base") }
            else { defaults.removeObject(forKey: "api_base") }
            HTTPCookieStorage.shared.deleteCookie(cookie)
            LessonPaths.activeScope = nil
        }

        var backendCalls = 0
        var independentCalls = 0
        let backendFailure = AISubscription(fetchProducts: {
            independentCalls += 1
            return []
        }, fetchAccess: { _ in
            backendCalls += 1
            throw Api.Failure(message: "fixture backend unavailable")
        }, retryPause: { _ in })
        await backendFailure.refresh()
        precondition(backendCalls == 1 && independentCalls == 3)
        precondition(backendFailure.message == "fixture backend unavailable" && backendFailure.productMessage != nil)

        var accessReply: CheckedContinuation<Api.AIAccess, Error>?
        let accountStore = AISubscription(fetchProducts: { [] }, fetchAccess: { _ in
            try await withCheckedThrowingContinuation { accessReply = $0 }
        }, retryPause: { _ in })
        let oldRefresh = Task { await accountStore.refresh() }
        while accessReply == nil { await Task.yield() }
        LessonPaths.activeScope = "subscription-fixture-b"
        accountStore.clearAccess()
        accessReply!.resume(returning: Api.AIAccess(["enabled": true, "subscribed": true]))
        await oldRefresh.value
        precondition(accountStore.access == nil && accountStore.message == nil && !accountStore.busy)

        var restoreFetches = 0
        let restoreStore = AISubscription(fetchAccess: { _ in
            restoreFetches += 1
            throw Offline.unavailable
        }, syncPurchases: { LessonPaths.activeScope = "subscription-fixture-c" })
        await restoreStore.restore()
        precondition(restoreFetches == 0 && restoreStore.access == nil && !restoreStore.busy,
                     "Restore must stop if the app account changes while Apple authenticates")
        print("PASS: subscription retries, partial plans, cancellation, independent loading, coalescing, storefront changes, backend failure, stale accounts and restore binding")
    }
}
