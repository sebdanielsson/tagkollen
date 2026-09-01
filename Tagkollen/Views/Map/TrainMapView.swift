import MapKit
import SwiftUI
import TrafikverketKit

/// The MapKit view itself: annotations for every live train inside the visible region.
struct TrainMapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var visibleRegion: MKCoordinateRegion
    @Binding var selectedTrainID: String?

    @Environment(LiveTrainStore.self) private var live
    @Environment(DelayIndex.self) private var delays
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Map(position: $camera, interactionModes: .all, selection: $selectedTrainID) {
            UserAnnotation()
            ForEach(visibleTrains) { train in
                Annotation(coordinate: train.clCoordinate, anchor: .center) {
                    TrainMarker(
                        train: train,
                        severity: delays.severity(for: train.key),
                        isSelected: train.id == selectedTrainID,
                        showLabel: showLabels
                    )
                } label: {
                    Text(train.displayNumber)
                }
                .annotationTitles(.hidden)
                .tag(train.id)
            }
        }
        .mapStyle(mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .mapControlVisibility(.automatic)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            delays.track(visibleTrains.compactMap(\.key))
        }
        .onChange(of: live.updateCount) { _, _ in
            delays.track(visibleTrains.compactMap(\.key))
        }
    }

    private var mapStyle: MapStyle {
        switch settings.mapAppearance {
        case .standard: .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .including([.publicTransport]))
        case .muted: .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }

    /// Only labels when zoomed in enough for them to be legible.
    private var showLabels: Bool {
        settings.showTrainLabels && visibleRegion.span.latitudeDelta < 2.2
    }

    private var visibleTrains: [LiveTrain] {
        let region = visibleRegion.padded(by: 0.25)
        return live.trains.filter { train in
            (settings.showInactiveTrains || train.isActive) && region.contains(train.clCoordinate)
        }
    }
}

extension MKCoordinateRegion {
    func padded(by fraction: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(180, span.latitudeDelta * (1 + fraction)),
                longitudeDelta: min(360, span.longitudeDelta * (1 + fraction))
            )
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude - center.latitude) <= span.latitudeDelta / 2
            && abs(coordinate.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}
