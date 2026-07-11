import Foundation

protocol UsageProviding {
    var id: ProviderID { get }
    /// Performs a minimal request and returns the current usage window.
    func fetchUsage(apiKey: String) async throws -> UsageSnapshot
}

enum UsageError: LocalizedError {
    case invalidKey
    case http(Int)
    case noRateLimitData
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid API key"
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

// MARK: - OpenAI

/// Reads OpenAI's `x-ratelimit-*-tokens` headers, which describe the token
/// budget for the current rolling window and how long until it resets.
struct OpenAIUsageProvider: UsageProviding {
    let id: ProviderID = .openai

    func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 401 { throw UsageError.invalidKey }

        let limit = RateLimitParsing.int(http, "x-ratelimit-limit-tokens")
        let remaining = RateLimitParsing.int(http, "x-ratelimit-remaining-tokens")
        let resetsAt = RateLimitParsing.string(http, "x-ratelimit-reset-tokens")
            .flatMap(RateLimitParsing.duration)
            .map { Date().addingTimeInterval($0) }

        guard let limit, let remaining, limit > 0 else {
            if !(200...299).contains(http.statusCode) && http.statusCode != 429 {
                throw UsageError.http(http.statusCode)
            }
            throw UsageError.noRateLimitData
        }

        let used = max(0, limit - remaining)
        return UsageSnapshot(provider: id,
                             fractionUsed: min(1, Double(used) / Double(limit)),
                             remainingTokens: remaining,
                             limitTokens: limit,
                             resetsAt: resetsAt,
                             lastUpdated: Date(),
                             errorMessage: nil)
    }
}

// MARK: - Anthropic

/// Reads Anthropic's `anthropic-ratelimit-tokens-*` headers. The reset header
/// is an RFC3339 timestamp for when the token bucket refills.
struct AnthropicUsageProvider: UsageProviding {
    let id: ProviderID = .anthropic

    func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-3-5-haiku-latest",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 401 { throw UsageError.invalidKey }

        let limit = RateLimitParsing.int(http, "anthropic-ratelimit-tokens-limit")
        let remaining = RateLimitParsing.int(http, "anthropic-ratelimit-tokens-remaining")
        let resetsAt = RateLimitParsing.string(http, "anthropic-ratelimit-tokens-reset")
            .flatMap(RateLimitParsing.date)

        guard let limit, let remaining, limit > 0 else {
            if !(200...299).contains(http.statusCode) && http.statusCode != 429 {
                throw UsageError.http(http.statusCode)
            }
            throw UsageError.noRateLimitData
        }

        let used = max(0, limit - remaining)
        return UsageSnapshot(provider: id,
                             fractionUsed: min(1, Double(used) / Double(limit)),
                             remainingTokens: remaining,
                             limitTokens: limit,
                             resetsAt: resetsAt,
                             lastUpdated: Date(),
                             errorMessage: nil)
    }
}

// MARK: - Google

/// Google's Generative Language API does not expose remaining-quota response
/// headers, so we can only validate the key. The snapshot reports no window and
/// the ring is drawn in an indeterminate style.
struct GoogleUsageProvider: UsageProviding {
    let id: ProviderID = .google

    func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("No response") }
        if http.statusCode == 400 || http.statusCode == 403 { throw UsageError.invalidKey }
        guard (200...299).contains(http.statusCode) else { throw UsageError.http(http.statusCode) }

        return UsageSnapshot(provider: id,
                             fractionUsed: 0,
                             remainingTokens: nil,
                             limitTokens: nil,
                             resetsAt: nil,
                             lastUpdated: Date(),
                             errorMessage: nil)
    }
}
