import Foundation

/// Persists the connected-provider list and the most recent usage snapshots in
/// the shared App Group container so the app and the widget read the same data.
enum UsageStore {
    private static let snapshotsKey = "usage.snapshots.v1"
    private static let connectedKey = "usage.connected.v1"

    // MARK: Connected providers

    static func connectedProviders() -> [ProviderID] {
        guard let defaults = AppGroup.sharedDefaults,
              let raw = defaults.array(forKey: connectedKey) as? [String] else {
            return []
        }
        // Preserve declaration order so the ring layout is stable.
        return ProviderID.allCases.filter { raw.contains($0.rawValue) }
    }

    static func setConnected(_ providers: [ProviderID]) {
        AppGroup.sharedDefaults?.set(providers.map(\.rawValue), forKey: connectedKey)
    }

    static func markConnected(_ provider: ProviderID) {
        var current = connectedProviders()
        if !current.contains(provider) { current.append(provider) }
        setConnected(current)
    }

    static func markDisconnected(_ provider: ProviderID) {
        setConnected(connectedProviders().filter { $0 != provider })
        var current = snapshots()
        current.removeValue(forKey: provider)
        saveSnapshots(current)
    }

    // MARK: Snapshots

    static func snapshots() -> [ProviderID: UsageSnapshot] {
        guard let defaults = AppGroup.sharedDefaults,
              let data = defaults.data(forKey: snapshotsKey),
              let decoded = try? JSONDecoder.usage.decode([UsageSnapshot].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.provider, $0) })
    }

    static func saveSnapshots(_ snapshots: [ProviderID: UsageSnapshot]) {
        guard let defaults = AppGroup.sharedDefaults,
              let data = try? JSONEncoder.usage.encode(Array(snapshots.values)) else { return }
        defaults.set(data, forKey: snapshotsKey)
    }

    static func save(_ snapshot: UsageSnapshot) {
        var current = snapshots()
        current[snapshot.provider] = snapshot
        saveSnapshots(current)
    }
}

private extension JSONDecoder {
    static let usage: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let usage: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
