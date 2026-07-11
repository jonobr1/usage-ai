import Foundation

/// A point-in-time reading of a provider's rate-limit / usage window.
///
/// Values are derived from each provider's rate-limit response headers, which
/// describe the token budget for the current window and when that window
/// resets — the closest public analogue to a "session" usage figure. See the
/// README for the per-provider details and limitations.
struct UsageSnapshot: Codable, Equatable, Identifiable {
    var provider: ProviderID
    /// Fraction of the window's token budget already consumed, clamped 0...1.
    var fractionUsed: Double
    var remainingTokens: Int?
    var limitTokens: Int?
    /// When the current window refreshes / resets.
    var resetsAt: Date?
    var lastUpdated: Date
    /// Non-nil when the last refresh failed; the UI shows a muted ring.
    var errorMessage: String?

    var id: String { provider.id }

    var percentUsed: Int { Int((fractionUsed * 100).rounded()) }

    /// True when we successfully talked to the provider but it did not report a
    /// usage window (e.g. Google). The ring is drawn in an indeterminate style.
    var hasWindow: Bool { limitTokens != nil }

    static func empty(_ provider: ProviderID) -> UsageSnapshot {
        UsageSnapshot(provider: provider,
                      fractionUsed: 0,
                      remainingTokens: nil,
                      limitTokens: nil,
                      resetsAt: nil,
                      lastUpdated: .distantPast,
                      errorMessage: nil)
    }
}
