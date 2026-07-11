import SwiftUI

/// A single usage ring in the style of the iOS "Batteries" widget: a track
/// circle, a colored progress arc, and a provider glyph in the center.
struct RingView: View {
    let provider: ProviderID
    let snapshot: UsageSnapshot?
    /// Diameter of the ring.
    var size: CGFloat = 60

    private var lineWidth: CGFloat { max(4, size * 0.11) }

    private var fraction: Double {
        min(1, max(0, snapshot?.fractionUsed ?? 0))
    }

    private var isConnected: Bool { snapshot != nil }
    private var hasError: Bool { snapshot?.errorMessage != nil }
    private var hasWindow: Bool { snapshot?.hasWindow ?? false }

    private var ringColor: Color {
        if !isConnected { return Color.secondary.opacity(0.25) }
        if hasError { return Color.secondary.opacity(0.5) }
        // Warn as the window fills up.
        switch fraction {
        case 0.9...: return .red
        case 0.75...: return .orange
        default: return provider.tint
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)

            if isConnected && hasWindow && !hasError {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ringColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else if isConnected && !hasWindow && !hasError {
                // Indeterminate window (e.g. Google): a faint dashed ring.
                Circle()
                    .stroke(provider.tint.opacity(0.5),
                            style: StrokeStyle(lineWidth: lineWidth,
                                               lineCap: .round,
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
        if !snapshot.hasWindow { return "\(provider.displayName), connected, usage unavailable" }
        return "\(provider.displayName), \(snapshot.percentUsed) percent of session used"
    }
}
