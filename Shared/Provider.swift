import SwiftUI

/// The AI services the app can connect to.
enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case openai
    case anthropic
    case google

    var id: String { rawValue }

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

    /// Keychain account under which this provider's API key is stored.
    var keychainAccount: String { "apiKey.\(rawValue)" }
}
