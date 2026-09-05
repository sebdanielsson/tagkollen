import SwiftUI

/// Small building blocks shared by the widgets and the Live Activity.
enum WidgetStyle {
    static func statusColor(_ status: TrainActivityAttributes.ContentState.Status, delay: TimeInterval?) -> Color {
        switch status {
        case .canceled: .red
        case .arrived: .green
        case .scheduled, .enRoute: DelaySeverity.of(delay: delay, canceled: false).color
        }
    }
}

/// A timetable time with the estimate beside it when they differ.
struct TimePair: View {
    let planned: Date?
    let expected: Date?
    var canceled = false
    var font: Font = .body

    var body: some View {
        HStack(spacing: 4) {
            Text(Format.clock(planned))
                .strikethrough(canceled || differs, color: canceled ? .red : .secondary)
                .foregroundStyle(canceled || differs ? .secondary : .primary)
            if !canceled, differs, let expected {
                Text(Format.clock(expected))
                    .fontWeight(.semibold)
                    .foregroundStyle(DelaySeverity.of(delay: expected.timeIntervalSince(planned ?? expected), canceled: false).color)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var differs: Bool {
        guard let planned, let expected else { return false }
        return abs(expected.timeIntervalSince(planned)) >= 60
    }
}

/// Track number chip.
struct TrackChip: View {
    let track: String?

    var body: some View {
        if let track, !track.isEmpty {
            Text(track)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: .rect(cornerRadius: 4))
                .accessibilityLabel(Text("Track \(track)"))
        }
    }
}
