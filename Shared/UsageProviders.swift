import Foundation

protocol UsageProviding {
    var id: ProviderID { get }
    /// Performs a minimal request and returns the current usage windows.
    func fetchUsage(credential: Credential) async throws -> UsageSnapshot
}

enum UsageError: LocalizedError {
    case invalidCredential
    case unsupportedAuth
    case http(Int)
    case noRateLimitData
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Sign in again"
        case .unsupportedAuth: return "Unsupported auth method"
        case .http(let code): return "HTTP \(code)"
        case .noRateLimitData: return "No usage data"
        case .network(let message): return message
        }
    }
}

enum UsageProviderFactory {
    static func provider(for id: ProviderID) -> UsageProviding {
        switch id {
        case .openai: return OpenAIUsageProvider()
        case .anthropic: return AnthropicUsageProvider()
        case .google: return GoogleUsageProvider()
        }
    }
}

/// Maps a family of rate-limit headers to a usage window kind.
private struct HeaderWindow {
    let kind: UsageWindowKind
    let limit: String
    let remaining: String
    let reset: String
}

private extension HTTPURLResponse {
    /// Builds a `UsageWindow` from a header family, if present.
    func window(_ spec: HeaderWindow) -> UsageWindow? {
        guard let limit = RateLimitParsing.int(self, spec.limit),
              let remaining = RateLimitParsing.int(self, spec.remaining),
              limit > 0 else { return nil }
        let used = max(0, limit - remaining)
        return UsageWindow(kind: spec.kind,
                           fractionUsed: min(1, Double(used) / Double(limit)),
                           resetsAt: RateLimitParsing.string(self, spec.reset).flatMap(RateLimitParsing.flexibleDate))
    }
}

// MARK: - OpenAI

/// With an API key, reads the `x-ratelimit-*-tokens` rate-limit window. With a
/// "Sign in with ChatGPT" OAuth token, the 5-hour and weekly plan windows would
/// come from Codex's usage endpoint — an undocumented surface, so that path
/// reports connected-but-unknown until an endpoint is wired in (see README).
struct OpenAIUsageProvider: UsageProviding {
    let id: ProviderID = .openai

    func fetchUsage(credential: Credential) async throws -> UsageSnapshot {
        switch credential {
        case .apiKey(let key):
            return try await rateLimitSnapshot(key: key)
        case .oauth:
            // Plan (5h / weekly) usage requires Codex's private usage endpoint.
            // Not wired in; report a connected-but-unknown snapshot.
            return UsageSnapshot(provider: id, windows: [], lastUpdated: Date(), errorMessage: nil)
        }
    }

    private func rateLimitSnapshot(key: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 401 { throw UsageError.invalidCredential }

        if let window = http.window(HeaderWindow(kind: .rateLimit,
                                                 limit: "x-ratelimit-limit-tokens",
                                                 remaining: "x-ratelimit-remaining-tokens",
                                                 reset: "x-ratelimit-reset-tokens")) {
            return UsageSnapshot(provider: id, windows: [window], lastUpdated: Date(), errorMessage: nil)
        }
        if !(200...299).contains(http.statusCode) && http.statusCode != 429 {
            throw UsageError.http(http.statusCode)
        }
        throw UsageError.noRateLimitData
    }
}

// MARK: - Anthropic

/// Authenticates with an OAuth access token from the Claude login flow and reads
/// whatever cap windows the response headers expose. The exact "unified" header
/// names are undocumented, so we probe a set of candidates and collect every one
/// that's present (5-hour session, weekly, and/or the classic per-minute bucket).
struct AnthropicUsageProvider: UsageProviding {
    let id: ProviderID = .anthropic

    private static let candidates: [HeaderWindow] = [
        HeaderWindow(kind: .fiveHour,
                     limit: "anthropic-ratelimit-unified-5h-limit",
                     remaining: "anthropic-ratelimit-unified-5h-remaining",
                     reset: "anthropic-ratelimit-unified-5h-reset"),
        HeaderWindow(kind: .weekly,
                     limit: "anthropic-ratelimit-unified-7d-limit",
                     remaining: "anthropic-ratelimit-unified-7d-remaining",
                     reset: "anthropic-ratelimit-unified-7d-reset"),
        HeaderWindow(kind: .fiveHour,
                     limit: "anthropic-ratelimit-unified-limit",
                     remaining: "anthropic-ratelimit-unified-remaining",
                     reset: "anthropic-ratelimit-unified-reset"),
        HeaderWindow(kind: .rateLimit,
                     limit: "anthropic-ratelimit-tokens-limit",
                     remaining: "anthropic-ratelimit-tokens-remaining",
                     reset: "anthropic-ratelimit-tokens-reset")
    ]

    func fetchUsage(credential: Credential) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch credential {
        case .oauth(let token):
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-3-5-haiku-latest",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 401 { throw UsageError.invalidCredential }

        // Collect one window per distinct kind (prefer the first/most specific).
        var byKind: [UsageWindowKind: UsageWindow] = [:]
        for spec in Self.candidates {
            if let window = http.window(spec), byKind[window.kind] == nil {
                byKind[window.kind] = window
            }
        }
        if !byKind.isEmpty {
            return UsageSnapshot(provider: id, windows: Array(byKind.values),
                                 lastUpdated: Date(), errorMessage: nil)
        }
        if (200...299).contains(http.statusCode) || http.statusCode == 429 {
            return UsageSnapshot(provider: id, windows: [], lastUpdated: Date(), errorMessage: nil)
        }
        throw UsageError.http(http.statusCode)
    }
}

// MARK: - Google

/// Authenticates with a Google OAuth access token (or API key) and validates
/// access. Google exposes no subscription usage window, so the ring shows
/// reachability only.
struct GoogleUsageProvider: UsageProviding {
    let id: ProviderID = .google

    func fetchUsage(credential: Credential) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
        request.httpMethod = "GET"
        switch credential {
        case .oauth(let token):
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        case .apiKey(let key):
            request.url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageError.invalidCredential }
        guard (200...299).contains(http.statusCode) else { throw UsageError.http(http.statusCode) }

        return UsageSnapshot(provider: id, windows: [], lastUpdated: Date(), errorMessage: nil)
    }
}
