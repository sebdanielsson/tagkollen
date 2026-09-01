import SwiftUI
import TrafikverketKit

/// A traffic message from Trafikverket, shown on journeys it affects.
struct MessageCard: View {
    let message: TrainMessage
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message.header ?? message.reasonCode?.first?.description ?? String(localized: "Traffic message"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            if let text = message.externalDescription, !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
            }
            if expanded {
                HStack(spacing: 12) {
                    if let start = message.startDateTime {
                        Label(Format.clock(start) + " " + Format.day(start), systemImage: "clock")
                    }
                    if let end = message.prognosticatedEndDateTimeTrafficImpact ?? message.endDateTime {
                        Label(Format.clock(end) + " " + Format.day(end), systemImage: "clock.badge.checkmark")
                    }
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
