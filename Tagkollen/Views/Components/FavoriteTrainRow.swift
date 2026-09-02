import SwiftUI

/// One saved train with its live status, used in the Saved list and the map card.
struct FavoriteTrainRow: View {
    let favorite: FavoriteTrain
    let journey: TrainJourney?
    @Environment(StationDirectory.self) private var stations

    var body: some View {
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
                }
                Text("\(stations.name(favorite.originSignature)) → \(stations.name(favorite.destinationSignature))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    let arrival = journey?.expectedArrival ?? favorite.scheduledArrival
                    Text("\(Format.clock(favorite.scheduledDeparture)) – \(Format.clock(arrival))")
                        .monospacedDigit()
                    if let next = journey?.nextStop, journey?.status == .enRoute {
                        Text("· \(String(localized: "Next")) \(stations.shortName(next.signature))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let journey {
                switch journey.status {
                case .arrived:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .canceled:
                    DelayBadge(delay: nil, canceled: true, compact: true)
                default:
                    DelayBadge(delay: journey.currentDelay, compact: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
