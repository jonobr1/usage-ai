import SwiftUI

/// How a provider is connected.
enum AuthMethod {
    case oauth
    case apiKey
}

/// The AI services the app can connect to.
enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case openai
    case anthropic
    case google

    var id: String { rawValue }

    /// The connection method the app offers for this provider.
    ///
    /// - Anthropic uses OAuth (Claude's login flow), which is what exposes the
    ///   5-hour session window.
    /// - Google offers OAuth once you supply an OAuth client ID (see
    ///   `OAuthConfig`); until then it can't be connected.
    /// - OpenAI has no OAuth for API/usage, so it uses an API key.
    var primaryAuth: AuthMethod {
        switch self {
        case .anthropic, .google: return .oauth
        case .openai: return .apiKey
        }
    }

    /// Whether an API key can also be used (in addition to / instead of OAuth).
    /// All three accept a key; for OpenAI/Anthropic it yields the API
    /// rate-limit window rather than the plan's 5h/weekly caps.
    var supportsAPIKey: Bool { true }

    /// What the ring's fill represents, for captions and accessibility.
    var windowLabel: String {
        switch self {
        case .anthropic: return "5h + weekly session"
        case .openai: return "5h + weekly (or rate limit)"
        case .google: return "API access"
        }
    }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        }
    }

    /// SF Symbol shown in the center of the ring.
    var symbolName: String {
        switch self {
        case .openai: return "circle.hexagongrid.fill"
        case .anthropic: return "sparkle"
        case .google: return "g.circle.fill"
        }
    }

    /// Ring tint, loosely evoking each brand.
    var tint: Color {
        switch self {
        case .openai: return Color(red: 0.06, green: 0.70, blue: 0.55)   // teal
        case .anthropic: return Color(red: 0.85, green: 0.47, blue: 0.30) // clay
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)    // blue
        }
    }

    /// Where to obtain an API key, shown on the connect screen.
    var keyURL: URL {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .google: return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

}
