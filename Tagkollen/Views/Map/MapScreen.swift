import MapKit
import os
import SwiftUI
import TrafikverketKit

/// The live map. On iPhone it is Apple Maps-like: full-bleed map, glass controls bottom-right and a
/// persistent bottom card for search, saved trains and details. On iPad the detail opens in an inspector.
struct MapScreen: View {
    @Environment(LiveTrainStore.self) private var live
    @Environment(StationDirectory.self) private var stations
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var camera: MapCameraPosition = .region(MapScreen.swedenRegion)
    @State private var visibleRegion: MKCoordinateRegion = MapScreen.swedenRegion
    @State private var selectedTrainID: String?
    @State private var selectedKey: TrainKey?
    @State private var selectedStation: TrainStation?
    @State private var showSettings = false
    @State private var sheetPath = NavigationPath()
    /// Typed shadow of `sheetPath`'s contents — `NavigationPath` is intentionally opaque (can't be
    /// read back), but restoring the map's selection/camera correctly when the user taps "back"
    /// needs to know what's now on top of the stack, so this is kept in lockstep with every push.
    @State private var routeStack: [MapSheetRoute] = []
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var sheetPresented = true
    @Namespace private var mapScope

    static let swedenRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 14.5, longitudeDelta: 14.5)
    )

    /// Height of the collapsed card: the search field with breathing room under the grabber.
    static let collapsedSheetHeight: CGFloat = 76
    static let sheetTopPadding: CGFloat = 16
    private static let logger = Logger(subsystem: "se.tagkollen.app", category: "MapScreen")

    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        Group {
            if isRegular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .onChange(of: selectedTrainID) { _, id in
            Self.logger.debug("selectedTrainID → \(id ?? "nil", privacy: .public)")
            guard let id, let train = live.train(id: id) else { return }
            selectedStation = nil
            selectedKey = train.key
            let route = MapSheetRoute.train(TrainSelection(key: train.key, liveID: id))
            if !isRegular, routeStack.last != route {
                // Append rather than replace: selecting a train from within an already-open
                // station board should push on top of it, so "back" returns to the board instead
                // of all the way to search. Skipped when this is already the top of the stack —
                // either a repeat tap, or this exact change is what a "back" restore just applied.
                sheetPath.append(route)
                routeStack.append(route)
                sheetDetent = .medium
            }
            withAnimation(.smooth) { camera = cameraFocusing(train.clCoordinate, spanDegrees: 0.45) }
        }
        .onChange(of: navigation.pendingMapFocus) { _, key in
            guard let key else { return }
            focus(on: key)
        }
        .onChange(of: navigation.pendingStationSignature, initial: true) { _, signature in
            // iPad routes station links to the Search tab; on iPhone the card shows the board.
            guard !isRegular, let signature, let station = stations.station(signature) else { return }
            navigation.pendingStationSignature = nil
            focus(on: station)
        }
        .onChange(of: stations.isLoaded) { _, loaded in
            guard loaded, !isRegular, let signature = navigation.pendingStationSignature,
                  let station = stations.station(signature) else { return }
            navigation.pendingStationSignature = nil
            focus(on: station)
        }
        .onChange(of: live.updateCount) { _, _ in
            if let key = navigation.pendingMapFocus {
                focus(on: key)
            } else if let selectedKey, selectedTrainID == nil, live.train(for: selectedKey) != nil {
                // The selected train had no live position when chosen; it just started reporting one.
                focus(on: selectedKey)
            }
        }
        .onChange(of: sheetPath) { _, path in
            Self.logger.debug("sheetPath → \(path.count) items")
            // A shorter path than our shadow copy means the user tapped "back" (pushes always grow
            // both together). Trim the shadow to match, then restore the map to whatever's now on
            // top — the previous station's board, an earlier train, or nothing at the root.
            guard path.count < routeStack.count else { return }
            routeStack.removeLast(routeStack.count - path.count)
            restoreSelection()
        }
    }

    private var map: some View {
        TrainMapView(
            camera: $camera,
            visibleRegion: $visibleRegion,
            selectedTrainID: $selectedTrainID,
            selectedKey: selectedKey,
            selectedStation: selectedStation,
            onSelectStation: { focus(on: $0) },
            scope: mapScope
        )
    }

    // MARK: iPhone

    private var compactLayout: some View {
        GeometryReader { geometry in
            compactMap(containerHeight: geometry.size.height)
        }
    }

    /// Bottom padding that keeps the controls just above the card at the current detent.
    private func controlsBottomPadding(containerHeight: CGFloat) -> CGFloat {
        switch sheetDetent {
        case .medium: containerHeight * 0.55 + 40 // medium ≈ 55 % of the safe-area height
        case .large: containerHeight + 200 // pushed off-screen
        default: Self.collapsedSheetHeight + 16
        }
    }

    private func compactMap(containerHeight: CGFloat) -> some View {
        map
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    StatusPill(state: live.state, count: live.trainCount, lastUpdate: live.lastUpdate)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .bottomTrailing) {
                MapControlsCluster(camera: $camera)
                    .padding(.trailing, 12)
                    .padding(.bottom, controlsBottomPadding(containerHeight: containerHeight))
                    .animation(.smooth(duration: 0.35), value: sheetDetent)
            }
            .mapScope(mapScope)
            .sheet(isPresented: $sheetPresented) {
                MapSheet(path: $sheetPath, detent: $sheetDetent, onSelectTrain: select, onSelectStation: { focus(on: $0) })
                    .presentationDetents([.height(Self.collapsedSheetHeight), .medium, .large], selection: $sheetDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationStack {
            map
                .safeAreaInset(edge: .top, spacing: 0) { regularTopOverlay }
                .navigationTitle("Map")
                .toolbar(.hidden, for: .navigationBar)
                .mapScope(mapScope)
                .sheet(isPresented: $showSettings) {
                    NavigationStack { SettingsView() }
                }
                .inspector(isPresented: inspectorBinding) {
                    if let selection = currentSelection {
                        NavigationStack {
                            TrainDetailView(key: selection.key, liveID: selection.liveID, onClose: clearSelection)
                        }
                        .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
                    }
                }
        }
    }

    private var regularTopOverlay: some View {
        HStack(alignment: .top) {
            StatusPill(state: live.state, count: live.trainCount, lastUpdate: live.lastUpdate)
            Spacer()
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .buttonStyle(.glass)
                        .labelStyle(.iconOnly)
                    MapControlsCluster(camera: $camera)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Selection plumbing

    private var currentSelection: TrainSelection? {
        if selectedTrainID == nil, selectedKey == nil {
            return nil
        }
        return TrainSelection(key: selectedKey, liveID: selectedTrainID)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { currentSelection != nil }, set: {
            if !$0 {
                clearSelection()
            }
        })
    }

    private func clearSelection() {
        selectedTrainID = nil
        selectedKey = nil
        selectedStation = nil
        if !isRegular {
            sheetPath = NavigationPath()
            routeStack = []
        }
    }

    /// Re-applies whatever is now on top of `routeStack` after a "back" tap trimmed it — restoring
    /// the map's selection and camera without pushing anything new onto the (already-correct) path.
    private func restoreSelection() {
        switch routeStack.last {
        case let .station(station):
            focus(on: station, pushingPath: false)
        case let .train(selection):
            if let key = selection.key {
                focus(on: key, pushingPath: false)
            } else {
                selectedTrainID = nil
                selectedKey = nil
            }
        case nil:
            selectedTrainID = nil
            selectedKey = nil
            selectedStation = nil
        }
    }

    /// Selects a train from a list or search result: zooms to it when it has a live position.
    private func select(_ key: TrainKey) {
        focus(on: key)
    }

    /// Frames a coordinate; on iPhone the point is shifted up so the medium-height card does not cover it.
    private func cameraFocusing(_ coordinate: CLLocationCoordinate2D, spanDegrees: CLLocationDegrees) -> MapCameraPosition {
        let offset = isRegular ? 0 : spanDegrees * 0.22
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - offset, longitude: coordinate.longitude)
        return .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)))
    }

    /// Selects a station: zooms the camera there, marks it on the map, and opens its board — used
    /// by search, quick stations and station deep links alike.
    private func focus(on station: TrainStation, pushingPath: Bool = true) {
        let alreadyShowing = !isRegular && selectedStation?.locationSignature == station.locationSignature
        selectedTrainID = nil
        selectedKey = nil
        selectedStation = station
        if pushingPath, !isRegular, !alreadyShowing {
            // Append rather than replace, so navigating here from within an already-open sheet
            // (e.g. a train's detail) leaves a "back" trail instead of discarding it. Skipped
            // entirely when this exact station is already on top, so re-tapping it (e.g. the
            // same quick-station icon) doesn't push a duplicate onto the path. Also skipped when
            // restoring a selection after "back" — the path is already correct in that case.
            sheetPath.append(MapSheetRoute.station(station))
            routeStack.append(.station(station))
            sheetDetent = .medium
        }
        if let coordinate = station.coordinate {
            withAnimation(.smooth) {
                camera = cameraFocusing(
                    CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    spanDegrees: 0.3
                )
            }
        }
    }

    private func focus(on key: TrainKey, pushingPath: Bool = true) {
        navigation.pendingMapFocus = nil
        selectedStation = nil
        if let train = live.train(for: key) {
            selectedKey = key
            selectedTrainID = train.id
            withAnimation(.smooth) {
                camera = cameraFocusing(train.clCoordinate, spanDegrees: 0.3)
            }
        } else if live.state.isLive || !live.trains.isEmpty {
            // No live position (yet); still open the timetable.
            let alreadyShowing = !isRegular && selectedKey == key && selectedTrainID == nil
            selectedKey = key
            selectedTrainID = nil
            if pushingPath, !isRegular, !alreadyShowing {
                // Append rather than replace: selecting a train from within an already-open
                // station board should push on top of it, so "back" returns to the board. Skipped
                // when this exact train is already showing, to avoid a duplicate path entry, and
                // when restoring a selection after "back" — the path is already correct then.
                sheetPath.append(MapSheetRoute.train(TrainSelection(key: key, liveID: nil)))
                routeStack.append(.train(TrainSelection(key: key, liveID: nil)))
                sheetDetent = .medium
            }
        } else {
            // Live data not loaded yet; try again once positions arrive.
            navigation.pendingMapFocus = key
        }
    }
}
