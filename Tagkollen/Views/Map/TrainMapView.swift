import MapKit
import SwiftUI
import TrafikverketKit

/// The MapKit view itself: annotations for every live train inside the visible region.
struct TrainMapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var visibleRegion: MKCoordinateRegion
    @Binding var selectedTrainID: String?
    var selectedKey: TrainKey?
    var scope: Namespace.ID

    @Environment(LiveTrainStore.self) private var live
    @Environment(JourneyStore.self) private var journeys
    @Environment(StationDirectory.self) private var stations
    @Environment(DelayIndex.self) private var delays
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    /// The trains actually handed to the map. Populated from `live.trains` outside of `body` (see
    /// `refreshDisplayedTrains`) so the nationwide position stream — which can update several times a
    /// second — only triggers a re-render when the filtered, on-screen set actually changes, instead
    /// of on every position update anywhere in Sweden.
    @State private var displayedTrains: [LiveTrain] = []
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        Map(position: $camera, interactionModes: .all, selection: $selectedTrainID, scope: scope) {
            UserAnnotation()
            if let journey = journeys.cached(selectedKey) {
                routeOverlay(for: journey)
            }
            ForEach(displayedTrains) { train in
                Annotation(coordinate: train.clCoordinate, anchor: .center) {
                    TrainMarker(
                        train: train,
                        severity: settings.colorMarkersByDelay ? delays.severity(for: train.key) : .unknown,
                        isSelected: train.id == selectedTrainID,
                        showLabel: showLabels,
                        compact: visibleRegion.span.latitudeDelta > 5
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
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            refreshDisplayedTrains()
        }
        .onChange(of: live.updateCount, initial: true) { _, _ in
            scheduleRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .onChange(of: selectedKey) { _, _ in
            fitCameraToRouteIfNeeded()
        }
        .onChange(of: journeys.cached(selectedKey)) { _, _ in
            fitCameraToRouteIfNeeded()
        }
    }

    /// Zoomed out over most/all of the country, hundreds of trains can be on screen at once and most
    /// barely move between ticks at that scale, so refreshing as often as the stream flushes (every
    /// ~400 ms) only burns main-thread time without a visible benefit. Zoomed into a city or line,
    /// refresh at full speed.
    private var refreshInterval: Duration {
        visibleRegion.span.latitudeDelta > 3 ? .milliseconds(1500) : Self.minRefreshInterval
    }

    private static let minRefreshInterval: Duration = .milliseconds(400)

    private func scheduleRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            try? await Task.sleep(for: refreshInterval)
            refreshTask = nil
            guard !Task.isCancelled else { return }
            refreshDisplayedTrains()
        }
    }

    /// Recomputes the on-screen train set and only touches `displayedTrains` (and re-tracks delays)
    /// when it actually changed, so an update elsewhere in the country doesn't re-render this map.
    private func refreshDisplayedTrains() {
        let next = visibleTrains
        guard next != displayedTrains else { return }
        displayedTrains = next
        delays.track(next.compactMap(\.key))
    }

    /// Frames the selected train's route when it has no live position to zoom to instead — e.g. a
    /// scheduled or already-arrived train opened from search or favorites. Live trains are already
    /// framed directly wherever they're selected (tapping a marker, `MapScreen.focus(on:)`), so this
    /// only fills the gap the schematic `routeOverlay` would otherwise leave off-screen.
    private func fitCameraToRouteIfNeeded() {
        guard let selectedKey, live.train(for: selectedKey) == nil,
              let journey = journeys.cached(selectedKey) else { return }
        let coordinates = journey.stops.compactMap { stations.station($0.signature)?.coordinate }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard let region = MKCoordinateRegion(fitting: coordinates) else { return }
        withAnimation(.smooth) { camera = .region(region) }
    }

    /// Schematic route (straight segments between stations) and stop dots for the selected train.
    @MapContentBuilder
    private func routeOverlay(for journey: TrainJourney) -> some MapContent {
        let points = journey.stops.compactMap { stop -> (TrainStop, CLLocationCoordinate2D)? in
            guard let c = stations.station(stop.signature)?.coordinate else { return nil }
            return (stop, CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
        }
        if points.count > 1 {
            MapPolyline(coordinates: points.map(\.1))
                .stroke(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 6]))
        }
        ForEach(points, id: \.0.id) { stop, coordinate in
            Annotation(coordinate: coordinate, anchor: .center) {
                Circle()
                    .fill(stop.isCanceled ? Color.red : (stop.hasPassed ? Color.secondary : Color.accentColor))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 1)
            } label: {
                Text(stations.shortName(stop.signature))
            }
            .annotationTitles(visibleRegion.span.latitudeDelta < 1.5 ? .visible : .hidden)
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

    /// Ambient trains for the current view, plus the explicitly selected one regardless of the
    /// active/region filters — a train the user searched for or saved shouldn't silently disappear
    /// just because Trafikverket marked it inactive (e.g. it already arrived) or it's off-screen
    /// mid-animation while the camera is still flying to it.
    private var visibleTrains: [LiveTrain] {
        let region = visibleRegion.padded(by: 0.25)
        var result = live.trains.filter { train in
            (settings.showInactiveTrains || train.isActive) && region.contains(train.clCoordinate)
        }
        if let selectedTrainID, !result.contains(where: { $0.id == selectedTrainID }),
           let selected = live.train(id: selectedTrainID) {
            result.append(selected)
        }
        return result
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

    /// A region tightly framing every coordinate, padded so edge stops and their labels aren't
    /// clipped. `nil` if there's nothing to fit.
    init?(fitting coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        self.init(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.15),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.15)
            )
        )
    }
}
