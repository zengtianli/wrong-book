import Foundation

/// Retry incomplete StoreKit responses without discarding plans that did arrive.
enum SubscriptionCatalog {
    @MainActor static func load<Item>(
        ids: [String],
        identify: (Item) -> String,
        fetch: () async throws -> [Item],
        pause: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> [Item] {
        var found: [String: Item] = [:]
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                for item in try await fetch() where ids.contains(identify(item)) {
                    found[identify(item)] = item
                }
                try Task.checkCancellation()
                if found.count == ids.count { break }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if attempt == 2 && found.isEmpty { throw error }
            }
            if attempt < 2 { try await pause(attempt == 0 ? 500_000_000 : 1_500_000_000) }
        }
        return ids.compactMap { found[$0] }
    }
}
