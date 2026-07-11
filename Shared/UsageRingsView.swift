import SwiftUI

/// A horizontal row of usage rings — the layout circled in the reference
/// screenshot (the iOS Batteries widget). Renders up to four connected
/// providers, each with a caption showing percent used and reset time.
struct UsageRingsView: View {
    let providers: [ProviderID]
    let snapshots: [ProviderID: UsageSnapshot]
    var ringSize: CGFloat = 58
    var showCaptions: Bool = true
    /// Reference date for computing "resets in …" (the timeline entry date).
    var now: Date = Date()

    var body: some View {
        if providers.isEmpty {
            EmptyRingsView(ringSize: ringSize)
        } else {
            HStack(alignment: .top, spacing: 14) {
                ForEach(providers) { provider in
                    VStack(spacing: 6) {
                        RingView(provider: provider,
                                 snapshot: snapshots[provider],
                                 size: ringSize)
                        if showCaptions {
                            caption(for: provider)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func caption(for provider: ProviderID) -> some View {
        let snapshot = snapshots[provider]
        VStack(spacing: 1) {
            Text(primaryCaption(snapshot))
                .font(.system(size: ringSize * 0.22, weight: .semibold))
                .foregroundStyle(.primary)
            Text(secondaryCaption(snapshot))
                .font(.system(size: ringSize * 0.19))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func primaryCaption(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "—" }
        if snapshot.errorMessage != nil { return "!" }
        if !snapshot.hasWindow { return provider(snapshot).displayName }
        return "\(snapshot.percentUsed)%"
    }

    private func secondaryCaption(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "tap to add" }
        if snapshot.errorMessage != nil { return "check key" }
        if !snapshot.hasWindow { return "connected" }
        return Formatting.shortReset(snapshot.resetsAt, now: now)
    }

    private func provider(_ snapshot: UsageSnapshot) -> ProviderID { snapshot.provider }
}

/// Placeholder shown when no providers are connected: greyed-out rings that
/// mirror the reference screenshot's empty slots.
struct EmptyRingsView: View {
    var ringSize: CGFloat = 58

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ProviderID.allCases) { provider in
                VStack(spacing: 6) {
                    RingView(provider: provider, snapshot: nil, size: ringSize)
                    Text("add")
                        .font(.system(size: ringSize * 0.2))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
