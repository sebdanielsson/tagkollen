import SwiftUI

/// One saved train with its live status, used in the Saved list and the map card.
/// Times, stations and status are those of the user's trip segment when one is set.
struct FavoriteTrainRow: View {
    let favorite: FavoriteTrain
    let journey: TrainJourney?
    @Environment(StationDirectory.self) private var stations

    private var snapshot: TrainSnapshot {
        var snapshot = TrainSnapshot(favorite: favorite)
        if let journey {
            snapshot.apply(journey)
        }
        return snapshot
    }

    var body: some View {
        let snapshot = snapshot
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(favorite.productName ?? String(localized: "Train")) \(favorite.ident)")
                        .font(.headline)
                    Text(Format.day(favorite.departureDate))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                    if favorite.segment != nil {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Your stops"))
                    }
                }
                Text("\(stations.name(snapshot.originSignature)) → \(stations.name(snapshot.destinationSignature))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(Format.clock(snapshot.scheduledDeparture)) – \(Format.clock(snapshot.bestArrival))")
                        .monospacedDigit()
                    if snapshot.status == .enRoute, let next = snapshot.nextStopSignature {
                        Text("· \(String(localized: "Next")) \(stations.shortName(next))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if journey != nil {
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
