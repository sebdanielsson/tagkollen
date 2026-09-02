import SwiftUI
import TrafikverketKit

/// A station sign/monitor message from Trafikverket, shown on journeys whose stations display it.
struct MessageCard: View {
    let message: TrainStationMessage
    @Environment(StationDirectory.self) private var stations
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(stations.name(message.locationCode))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let start = message.startDateTime {
                    Text(Format.clock(start))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            Text(message.displayText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 3)
            if expanded, let end = message.endDateTime {
                Label {
                    Text("Until \(Format.clock(end)) \(Format.day(end))")
                } icon: {
                    Image(systemName: "clock.badge.checkmark")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .accessibilityAddTraits(.isButton)
    }
}
