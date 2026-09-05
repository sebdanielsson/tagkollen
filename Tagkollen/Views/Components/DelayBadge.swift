import SwiftUI

/// Colour-coded delay chip: green on time, orange minor, red major, grey unknown.
struct DelayBadge: View {
    var delay: TimeInterval?
    var canceled = false
    var compact = false

    var body: some View {
        if canceled {
            label(String(localized: "Canceled"), color: .red, icon: "xmark.circle.fill")
        } else if let text = Format.delay(delay) {
            label(text, color: severityColor, icon: nil)
        }
    }

    private var severityColor: Color {
        DelaySeverity.of(delay: delay, canceled: canceled).color
    }

    private func label(_ text: String, color: Color, icon: String?) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).imageScale(.small)
            }
            Text(text)
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(color.opacity(0.14), in: .capsule)
        .accessibilityLabel(canceled ? Text("Canceled") : Text(text))
    }
}

extension DelaySeverity {
    var color: Color {
        switch self {
        case .unknown: .secondary
        case .onTime: .green
        case .minor: .orange
        case .major: .red
        case .canceled: .red
        }
    }

    /// Marker tint on the map; unknown falls back to the accent colour.
    var markerColor: Color {
        switch self {
        case .unknown: .accentColor
        case .onTime: .green
        case .minor: .orange
        case .major: .red
        case .canceled: .gray
        }
    }
}
