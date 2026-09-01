import MapKit
import SwiftUI

/// Mini-map with the train's current GPS fix plus speed / heading / age.
struct LivePositionCard: View {
    let train: LiveTrain
    var journey: TrainJourney?
    @Environment(StationDirectory.self) private var stations

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: train.clCoordinate, distance: 25000)), interactionModes: []) {
                Annotation(coordinate: train.clCoordinate, anchor: .center) {
                    TrainMarker(train: train, severity: .unknown, isSelected: true, showLabel: false)
                } label: { EmptyView() }
                    .annotationTitles(.hidden)
                if let journey {
                    stopMarkers(for: journey)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .frame(height: 170)
            .allowsHitTesting(false)
            .id(train.id + "\(train.timestamp?.timeIntervalSince1970 ?? 0)")

            HStack(spacing: 0) {
                stat(value: Format.speed(train.speed) ?? "–", label: "Speed", icon: "speedometer")
                Divider().frame(height: 28)
                stat(value: Format.compass(train.bearing) ?? "–", label: "Heading", icon: "location.north.line")
                Divider().frame(height: 28)
                stat(value: train.timestamp.map { Format.relative($0) } ?? "–", label: "Position", icon: "dot.radiowaves.left.and.right")
            }
            .padding(.vertical, 10)
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @MapContentBuilder
    private func stopMarkers(for journey: TrainJourney) -> some MapContent {
        ForEach(journey.stops) { stop in
            if let coord = stations.station(stop.signature)?.coordinate {
                Annotation(coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude), anchor: .center) {
                    Circle()
                        .fill(stop.hasPassed ? Color.secondary : Color.accentColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                } label: { Text(stations.shortName(stop.signature)) }
            }
        }
    }

    private func stat(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
    }
}
