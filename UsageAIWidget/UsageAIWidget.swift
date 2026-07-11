import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let providers: [ProviderID]
    let snapshots: [ProviderID: UsageSnapshot]

    static let placeholder = UsageEntry(
        date: Date(),
        providers: [.openai, .anthropic, .google],
        snapshots: [
            .openai: UsageSnapshot(provider: .openai, fractionUsed: 0.32,
                                   remainingTokens: 68_000, limitTokens: 100_000,
                                   resetsAt: Date().addingTimeInterval(3600),
                                   lastUpdated: Date(), errorMessage: nil),
            .anthropic: UsageSnapshot(provider: .anthropic, fractionUsed: 0.71,
                                      remainingTokens: 29_000, limitTokens: 100_000,
                                      resetsAt: Date().addingTimeInterval(1500),
                                      lastUpdated: Date(), errorMessage: nil),
            .google: UsageSnapshot(provider: .google, fractionUsed: 0,
                                   remainingTokens: nil, limitTokens: nil,
                                   resetsAt: nil, lastUpdated: Date(), errorMessage: nil)
        ]
    )
}

// MARK: - Timeline provider

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            await UsageRefresher.refreshAll()
            let entry = currentEntry()
            // Refresh again shortly before the soonest window resets, but at
            // least every 15 minutes and at most hourly.
            let soonestReset = entry.snapshots.values
                .compactMap(\.resetsAt)
                .filter { $0 > entry.date }
                .min()
            let floor = entry.date.addingTimeInterval(15 * 60)
            let ceiling = entry.date.addingTimeInterval(60 * 60)
            let next = min(max(soonestReset ?? ceiling, floor), ceiling)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry() -> UsageEntry {
        UsageEntry(date: Date(),
                   providers: UsageStore.connectedProviders(),
                   snapshots: UsageStore.snapshots())
    }
}

// MARK: - Views

struct UsageAIWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallUsageView(entry: entry)
        default:
            MediumUsageView(entry: entry)
        }
    }
}

/// Medium widget: the row-of-rings layout from the reference screenshot.
struct MediumUsageView: View {
    var entry: UsageEntry

    private var visible: [ProviderID] { Array(entry.providers.prefix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Usage AI", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if entry.providers.isEmpty {
                UnconfiguredView()
            } else {
                HStack {
                    Spacer(minLength: 0)
                    UsageRingsView(providers: visible,
                                   snapshots: entry.snapshots,
                                   ringSize: 56,
                                   now: entry.date)
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(for: .widget) { WidgetBackgroundView() }
    }
}

/// Small widget: focuses on the busiest connected provider.
struct SmallUsageView: View {
    var entry: UsageEntry

    private var focus: ProviderID? {
        entry.providers.max { lhs, rhs in
            (entry.snapshots[lhs]?.fractionUsed ?? 0) < (entry.snapshots[rhs]?.fractionUsed ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let focus {
                RingView(provider: focus, snapshot: entry.snapshots[focus], size: 72)
                VStack(spacing: 1) {
                    Text(title(for: focus)).font(.headline)
                    Text(subtitle(for: focus)).font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                UnconfiguredView()
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { WidgetBackgroundView() }
    }

    private func title(for provider: ProviderID) -> String {
        let snapshot = entry.snapshots[provider]
        if snapshot?.errorMessage != nil { return provider.displayName }
        if snapshot?.hasWindow == true { return "\(snapshot?.percentUsed ?? 0)%" }
        return provider.displayName
    }

    private func subtitle(for provider: ProviderID) -> String {
        let snapshot = entry.snapshots[provider]
        if snapshot?.errorMessage != nil { return "check API key" }
        if snapshot?.hasWindow == true {
            return "\(provider.displayName) · \(Formatting.shortReset(snapshot?.resetsAt, now: entry.date))"
        }
        return "connected"
    }
}

struct UnconfiguredView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "circle.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Usage AI to connect a service")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

/// Background matching the muted look of the reference widget. Uses the
/// `WidgetBackground` color set (light/dark aware) from the asset catalog.
struct WidgetBackgroundView: View {
    var body: some View {
        Color("WidgetBackground")
    }
}

// MARK: - Widget

struct UsageAIWidget: Widget {
    let kind = "UsageAIWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageAIWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Session token usage for your connected AI services, and when each window resets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    UsageAIWidget()
} timeline: {
    UsageEntry.placeholder
}
