import SwiftUI

/// Lets the user say where they board and get off, so alerts and the Live Activity ignore the
/// rest of the run.
struct TripSegmentSection: View {
    let favorite: FavoriteTrain
    let journey: TrainJourney
    var onChange: () -> Void
    @Environment(StationDirectory.self) private var stations

    var body: some View {
        Section {
            Picker(selection: boarding) {
                Text("Train's first station").tag(String?.none)
                ForEach(journey.stops.dropLast()) { stop in
                    Text(stations.name(stop.signature)).tag(Optional(stop.signature))
                }
            } label: {
                Label("Board at", systemImage: "figure.walk.arrival")
            }
            Picker(selection: alighting) {
                Text("Train's last station").tag(String?.none)
                ForEach(journey.stops.dropFirst()) { stop in
                    Text(stations.name(stop.signature)).tag(Optional(stop.signature))
                }
            } label: {
                Label("Get off at", systemImage: "figure.walk.departure")
            }
        } header: {
            Text("Your stops")
        } footer: {
            Text("Delays, alerts, widgets and the Live Activity then only consider this part of the trip.")
        }
    }

    private var boarding: Binding<String?> {
        Binding(
            get: { favorite.boardingSignature },
            set: { newValue in
                var alighting = favorite.alightingSignature
                if let newValue, let alighting, !isOrdered(newValue, alighting) {
                    _ = alighting
                }
                if let newValue, let current = alighting, !isOrdered(newValue, current) {
                    alighting = nil
                }
                favorite.setSegment(boarding: newValue, alighting: alighting, journey: journey)
                onChange()
            }
        )
    }

    private var alighting: Binding<String?> {
        Binding(
            get: { favorite.alightingSignature },
            set: { newValue in
                var boarding = favorite.boardingSignature
                if let newValue, let current = boarding, !isOrdered(current, newValue) {
                    boarding = nil
                }
                favorite.setSegment(boarding: boarding, alighting: newValue, journey: journey)
                onChange()
            }
        )
    }

    /// True when `first` comes before `second` along the run.
    private func isOrdered(_ first: String, _ second: String) -> Bool {
        guard let a = journey.stops.firstIndex(where: { $0.signature == first }),
              let b = journey.stops.lastIndex(where: { $0.signature == second }) else { return true }
        return a < b
    }
}
