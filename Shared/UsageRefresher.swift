import Foundation

/// Refreshes usage for all connected providers and persists the results to the
/// shared store. Used by both the app (on demand) and the widget (on timeline
/// refresh).
enum UsageRefresher {
    /// Fetches usage for every connected provider concurrently, writes the
    /// snapshots to the shared store, and returns the full current set.
    @discardableResult
    static func refreshAll() async -> [UsageSnapshot] {
        let providers = UsageStore.connectedProviders()

        let fetched = await withTaskGroup(of: UsageSnapshot?.self) { group -> [UsageSnapshot] in
            for id in providers {
                group.addTask { await refresh(id) }
            }
            var results: [UsageSnapshot] = []
            for await snapshot in group where snapshot != nil {
                results.append(snapshot!)
            }
            return results
        }

        var stored = UsageStore.snapshots()
        for snapshot in fetched { stored[snapshot.provider] = snapshot }
        UsageStore.saveSnapshots(stored)
        return UsageStore.connectedProviders().map { stored[$0] ?? .empty($0) }
    }

    /// Refreshes a single provider. On failure, the previous snapshot is kept
    /// but annotated with the error so the ring can be muted rather than blank.
    static func refresh(_ id: ProviderID) async -> UsageSnapshot? {
        guard let key = KeychainStore.read(account: id.keychainAccount) else { return nil }
        let provider = UsageProviderFactory.provider(for: id)
        do {
            return try await provider.fetchUsage(apiKey: key)
        } catch {
            var snapshot = UsageStore.snapshots()[id] ?? .empty(id)
            snapshot.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            snapshot.lastUpdated = Date()
            return snapshot
        }
    }
}
