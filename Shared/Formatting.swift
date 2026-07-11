import Foundation

enum Formatting {
    /// "resets in 2h 14m" style string for the app UI.
    static func resetString(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "no reset window" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "resets now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "resets in \(minutes)m" }
        return "resets in <1m"
    }

    /// Compact "2h" / "14m" string for the widget footer.
    static func shortReset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    static func tokens(_ count: Int?) -> String {
        guard let count else { return "—" }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
