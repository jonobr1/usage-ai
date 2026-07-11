import Foundation

/// Helpers for reading rate-limit information out of HTTP response headers.
enum RateLimitParsing {
    static func int(_ http: HTTPURLResponse, _ name: String) -> Int? {
        guard let value = http.value(forHTTPHeaderField: name)?
            .trimmingCharacters(in: .whitespaces) else { return nil }
        return Int(value)
    }

    static func string(_ http: HTTPURLResponse, _ name: String) -> String? {
        http.value(forHTTPHeaderField: name)
    }

    /// Parses ISO-8601 / RFC3339 timestamps (Anthropic reset headers).
    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// Parses Go-style durations such as "6ms", "1s", "2m59s", "1h2m3s"
    /// (the format OpenAI uses for its `x-ratelimit-reset-*` headers) and
    /// returns the total number of seconds.
    static func duration(_ string: String) -> TimeInterval? {
        let lowered = string.lowercased()
        var total: TimeInterval = 0
        var numberBuffer = ""
        var unitBuffer = ""
        var matchedAny = false

        func flush() {
            guard let value = Double(numberBuffer), !unitBuffer.isEmpty else { return }
            switch unitBuffer {
            case "ms": total += value / 1000
            case "s":  total += value
            case "m":  total += value * 60
            case "h":  total += value * 3600
            case "d":  total += value * 86400
            default:   break
            }
            matchedAny = true
            numberBuffer = ""
            unitBuffer = ""
        }

        for char in lowered {
            if char.isNumber || char == "." {
                if !unitBuffer.isEmpty { flush() }   // a new number begins after a unit
                numberBuffer.append(char)
            } else if char.isLetter {
                unitBuffer.append(char)
            }
        }
        flush()
        return matchedAny ? total : nil
    }
}
