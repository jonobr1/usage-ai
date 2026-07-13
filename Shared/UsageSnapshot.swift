import Foundation

/// A usage cap tier. Modern subscription plans enforce several at once — a short
/// rolling window (e.g. 5-hour) *and* a weekly window — so a provider reports one
/// `UsageWindow` per tier it exposes.
enum UsageWindowKind: String, Codable, CaseIterable {
    case fiveHour
    case weekly
    case rateLimit   // short API rate-limit bucket (fallback when no plan window)

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "Wk"
        case .rateLimit: return "Rate"
        }
    }

    var longLabel: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .rateLimit: return "Rate limit"
        }
    }

    /// Ordering for display; the shorter/more-urgent window sorts first.
    var priority: Int {
        switch self {
        case .fiveHour: return 0
        case .weekly: return 1
        case .rateLimit: return 2
        }
    }
}

/// A single cap tier's state.
struct UsageWindow: Codable, Equatable, Identifiable {
    var kind: UsageWindowKind
    /// Fraction of the window's budget already consumed, clamped 0...1.
    var fractionUsed: Double
    /// When this window resets.
    var resetsAt: Date?

    var id: String { kind.rawValue }
    var fractionRemaining: Double { max(0, min(1, 1 - fractionUsed)) }
    var percentUsed: Int { Int((min(1, max(0, fractionUsed)) * 100).rounded()) }
    var percentRemaining: Int { max(0, 100 - percentUsed) }
}

/// A point-in-time reading of a provider's usage across all the cap tiers it
/// exposes.
struct UsageSnapshot: Codable, Equatable, Identifiable {
    var provider: ProviderID
    var windows: [UsageWindow]
    var lastUpdated: Date
    /// Non-nil when the last refresh failed; the UI shows a muted ring.
    var errorMessage: String?

    var id: String { provider.id }
    var hasWindow: Bool { !windows.isEmpty }

    /// The window that drives the main ring: the most-depleted one (closest to
    /// its cap), tie-broken by priority (5h before weekly).
    var primaryWindow: UsageWindow? {
        windows.max { lhs, rhs in
            if lhs.fractionUsed != rhs.fractionUsed { return lhs.fractionUsed < rhs.fractionUsed }
            return lhs.kind.priority > rhs.kind.priority
        }
    }

    /// Windows in display order (5h, weekly, rate).
    var orderedWindows: [UsageWindow] {
        windows.sorted { $0.kind.priority < $1.kind.priority }
    }

    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    static func empty(_ provider: ProviderID) -> UsageSnapshot {
        UsageSnapshot(provider: provider, windows: [], lastUpdated: .distantPast, errorMessage: nil)
    }
}
