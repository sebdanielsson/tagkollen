import SwiftUI

/// One recently opened train, laid out like `FavoriteTrainRow` so the two tabs of the map card
/// read as one list. Everything but the live status comes from the stored record, so the row is
/// complete before any journey is loaded.
struct RecentTrainRow: View {
    let recent: RecentTrain
    let journey: TrainJourney?
    @Environment(StationDirectory.self) private var stations

    private var snapshot: TrainSnapshot? {
        journey.map { TrainSnapshot(journey: $0) }
    }

    var body: some View {
        let snapshot = snapshot
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(recent.productName ?? String(localized: "Train")) \(recent.ident)")
                        .font(.headline)
                    Text(Format.day(recent.departureDate))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                    TrackChip(track: snapshot?.currentTrack)
                }
                Text("\(stations.name(recent.originSignature)) → \(stations.name(recent.destinationSignature))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(Format.clock(recent.scheduledDeparture)) – \(Format.clock(recent.scheduledArrival))")
                        .monospacedDigit()
                    if let snapshot, snapshot.status == .enRoute, let next = snapshot.nextStopSignature {
                        Text("· \(String(localized: "Next")) \(stations.shortName(next))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let snapshot {
                switch snapshot.status {
                case .arrived:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .canceled:
                    DelayBadge(delay: nil, canceled: true, compact: true)
                default:
                    DelayBadge(delay: snapshot.delay, compact: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
