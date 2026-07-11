import SwiftUI

/// A horizontal row of usage rings — the layout circled in the reference
/// screenshot (the iOS Batteries widget). Renders up to four connected
/// providers, each with a caption showing **remaining** for every cap tier
/// (e.g. "5h 99%" / "Wk 100%") and the soonest reset.
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
                    .frame(maxWidth: ringSize * 1.5)
                }
            }
        }
    }

    @ViewBuilder
    private func caption(for provider: ProviderID) -> some View {
        let snapshot = snapshots[provider]
        VStack(spacing: 1) {
            if let snapshot, snapshot.errorMessage != nil {
                captionLine("!", "check sign-in")
            } else if let snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.orderedWindows.prefix(2)) { window in
                    captionLine("\(window.kind.shortLabel) \(window.percentRemaining)%",
                                nil)
                }
            } else if snapshot != nil {
                captionLine(provider.displayName, "connected")
            } else {
                captionLine("—", "tap to add")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private func captionLine(_ primary: String, _ secondary: String?) -> some View {
        Text(primary)
            .font(.system(size: ringSize * 0.2, weight: .semibold))
            .foregroundStyle(.primary)
        if let secondary {
            Text(secondary)
                .font(.system(size: ringSize * 0.18))
                .foregroundStyle(.secondary)
        }
    }
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
