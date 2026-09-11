import SwiftUI

/// Small live/connection indicator shown on the map.
struct StatusPill: View {
    var state: LiveTrainStore.ConnectionState
    var count: Int
    var lastUpdate: Date?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay {
                    if state == .streaming {
                        Circle().stroke(color.opacity(0.5), lineWidth: 2).scaleEffect(1.8)
                            .phaseAnimator([false, true]) { view, phase in
                                view.opacity(phase ? 0 : 1).scaleEffect(phase ? 2.4 : 1.2)
                            } animation: { _ in .easeOut(duration: 1.6) }
                    }
                }
            Text(title)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .idle, .connecting: .secondary
        case .streaming: .green
        case .polling: .yellow
        case .failed: .red
        }
    }

    private var title: String {
        switch state {
        case .idle: String(localized: "Paused")
        case .connecting: String(localized: "Connecting…")
        case .streaming, .polling: String(localized: "\(count) trains live")
        case .failed: String(localized: "Offline")
        }
    }
}
