import SwiftUI

/// The track a train uses at a station, boxed so it reads as a platform number and not as one more
/// time or delay. Nothing is drawn without a track, so callers can pass an optional unwrapped.
struct TrackChip: View {
    let track: String?
    /// Widget-sized: the same chip a step smaller, for rows that are already tight.
    var compact = false

    var body: some View {
        if let track, !track.isEmpty {
            Text(track)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, compact ? 5 : 6)
                .padding(.vertical, compact ? 1 : 2)
                .background(.quaternary, in: .rect(cornerRadius: compact ? 4 : 5))
                .accessibilityLabel(Text("Track \(track)"))
        }
    }
}
