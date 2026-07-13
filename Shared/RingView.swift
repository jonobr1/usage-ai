import SwiftUI

/// A single usage ring in the style of the iOS "Batteries" widget: a track
/// circle, an arc showing how much of the most-depleted window is **remaining**,
/// and a provider glyph in the center. Low remaining reads red, like a battery.
struct RingView: View {
    let provider: ProviderID
    let snapshot: UsageSnapshot?
    /// Diameter of the ring.
    var size: CGFloat = 60

    private var lineWidth: CGFloat { max(4, size * 0.11) }

    private var window: UsageWindow? { snapshot?.primaryWindow }
    private var isConnected: Bool { snapshot != nil }
    private var hasError: Bool { snapshot?.errorMessage != nil }
    private var hasWindow: Bool { window != nil }

    /// Fraction of the ring to fill = fraction of budget remaining.
    private var remaining: Double { window?.fractionRemaining ?? 0 }

    private var ringColor: Color {
        if !isConnected { return Color.secondary.opacity(0.25) }
        if hasError { return Color.secondary.opacity(0.5) }
        switch remaining {
        case ..<0.10: return .red
        case ..<0.25: return .orange
        default: return provider.tint
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)

            if isConnected && hasWindow && !hasError {
                Circle()
                    .trim(from: 0, to: max(0.001, remaining))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else if isConnected && !hasWindow && !hasError {
                // Connected but no usage window reported: faint dashed ring.
                Circle()
                    .stroke(provider.tint.opacity(0.5),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                               dash: [2, size * 0.10]))
            }

            Image(systemName: provider.symbolName)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(isConnected ? provider.tint : Color.secondary.opacity(0.5))
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let snapshot else { return "\(provider.displayName), not connected" }
        if snapshot.errorMessage != nil { return "\(provider.displayName), needs attention" }
        guard !snapshot.windows.isEmpty else {
            return "\(provider.displayName), connected, usage unavailable"
        }
        let parts = snapshot.orderedWindows.map { "\($0.kind.longLabel) \($0.percentRemaining) percent remaining" }
        return "\(provider.displayName): " + parts.joined(separator: ", ")
    }
}
