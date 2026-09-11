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
    /// Typed shadow of `sheetPath`, kept in lockstep with every push — see `MapNavigationStack`.
    @State private var navigationStack = MapNavigationStack()
    /// A focus request this screen deferred because live positions hadn't arrived yet. Kept here
    /// rather than in `AppNavigation.pendingMapFocus`, which means "something outside the map
    /// asked for this" and resets the card's trail — a retry of our own must not do that.
    @State private var deferredFocus: DeferredFocus?
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
    private static let logger = Logger(subsystem: "se.tagradar.app", category: "MapScreen")

    private struct DeferredFocus {
        let key: TrainKey
        let pushesPath: Bool
    }

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
            deferredFocus = nil
            selectedKey = train.key
            push(.train(TrainSelection(key: train.key, liveID: id)), if: true)
            withAnimation(.smooth) { camera = cameraFocusing(train.clCoordinate, spanDegrees: 0.45) }
        }
        .onChange(of: navigation.pendingMapFocus) { _, key in
            guard let key else { return }
            startFreshTrail()
            focus(on: key)
        }
        .onChange(of: navigation.pendingStationSignature, initial: true) { _, signature in
            // iPad routes station links to the Search tab; on iPhone the card shows the board.
            guard !isRegular, let signature, let station = stations.station(signature) else { return }
            navigation.pendingStationSignature = nil
            startFreshTrail()
            focus(on: station)
        }
        .onChange(of: stations.revision) { _, _ in
            // Same reason as the pending signature above, but for a link that arrived before the
            // station it names was in the directory. `revision` fires for the disk cache and the
            // live refresh alike, where `isLoaded` only ever changes on the first of the two.
            guard !isRegular, let signature = navigation.pendingStationSignature,
                  let station = stations.station(signature) else { return }
            navigation.pendingStationSignature = nil
            startFreshTrail()
            focus(on: station)
        }
        .onChange(of: live.updateCount) { _, _ in
            if let key = navigation.pendingMapFocus {
                startFreshTrail()
                focus(on: key)
            } else if let deferred = deferredFocus {
                // Our own retry, so the card keeps whatever trail it already had.
                focus(on: deferred.key, pushingPath: deferred.pushesPath)
            } else if let selectedKey, selectedTrainID == nil, live.train(for: selectedKey) != nil {
                // The selected train had no live position when chosen; it just started reporting one.
                focus(on: selectedKey)
            }
        }
        .onChange(of: sheetPath) { _, path in
            Self.logger.debug("sheetPath → \(path.count) items")
            // A shorter path than our shadow copy means the user tapped "back" (pushes already
            // grow both together, so this only fires for a pop). Trim the shadow to match, then
            // restore the map to whatever's now on top — the previous station's board, an earlier
            // train, or nothing at the root.
            guard path.count < navigationStack.routes.count else {
                if path.count > navigationStack.routes.count {
                    // Something appended without going through `push`, so the shadow is now
                    // shallower than the real stack and the next "back" would restore the wrong
                    // screen. Nothing does today; this is here so it can't fail silently.
                    Self.logger.error("sheetPath grew to \(path.count) past the shadow's \(navigationStack.routes.count)")
                }
                return
            }
            navigationStack.trim(to: path.count)
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
                    inspectorDetail
                        .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
                }
        }
    }

    /// What the iPad inspector shows for the current selection. Stations get their board here for
    /// the same reason trains get their detail: on iPad there is no bottom card to push onto, so
    /// without this a tapped station dot would only move the camera.
    @ViewBuilder
    private var inspectorDetail: some View {
        if let selectedStation {
            // Keyed on the station: without this a different station would reuse this stack, so
            // the panel would keep showing a train pushed from the previous station's board.
            NavigationStack {
                // No `onSelectTrain` on purpose: unlike the iPhone card, the inspector is its own
                // navigation stack, so a train pushes on top of the board with a back button and
                // the map keeps showing the station the user is reading about.
                StationBoardView(station: selectedStation)
                    .toolbar {
                        // The inspector has no dismiss chrome of its own, and unlike a train
                        // detail the board has no Close button, so without this the panel can
                        // only be closed by selecting something else.
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "xmark", action: clearSelection)
                        }
                    }
            }
            .id(selectedStation.locationSignature)
        } else if let selection = currentSelection {
            NavigationStack {
                TrainDetailView(key: selection.key, liveID: selection.liveID, onClose: clearSelection)
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
        Binding(get: { currentSelection != nil || selectedStation != nil }, set: {
            if !$0 {
                clearSelection()
            }
        })
    }

    private func clearSelection() {
        selectedTrainID = nil
        selectedKey = nil
        selectedStation = nil
        deferredFocus = nil
        startFreshTrail()
    }

    /// Empties the card's navigation trail and its shadow together. Also used when focus arrives
    /// from outside the map (a deep link, or a link from another tab): whatever the card was
    /// showing belongs to an older, unrelated bit of browsing, so "back" shouldn't walk into it.
    /// Runs in the regular size class too, where the card isn't on screen — cheap, and it keeps
    /// the two representations from ever disagreeing.
    private func startFreshTrail() {
        guard !sheetPath.isEmpty || !navigationStack.isEmpty else { return }
        sheetPath = NavigationPath()
        navigationStack.reset()
    }

    /// Re-applies whatever is now on top of the navigation stack after a "back" tap trimmed it —
    /// restoring the map's selection and camera without pushing anything new onto the
    /// (already-correct) path.
    private func restoreSelection() {
        switch navigationStack.top {
        case let .station(station):
            focus(on: station, pushingPath: false)
        case let .train(selection):
            if let key = selection.key {
                focus(on: key, pushingPath: false)
            } else {
                // A train with no advertised number (freight or service) has no key to re-focus
                // by, but its live id still selects the marker and re-centres the camera.
                selectedStation = nil
                selectedKey = nil
                selectedTrainID = selection.liveID
            }
        case nil:
            selectedTrainID = nil
            selectedKey = nil
            selectedStation = nil
            deferredFocus = nil
        }
    }

    /// Appends to the card's navigation trail, keeping `sheetPath` and its typed shadow in
    /// lockstep. Append rather than replace: selecting a train from within an already-open station
    /// board pushes on top of it, so "back" returns to the board instead of all the way to search.
    /// Does nothing in the regular size class (no card), when the caller is restoring a selection
    /// after "back" (`shouldPush` false), or when that screen is already on top.
    private func push(_ route: MapSheetRoute, if shouldPush: Bool) {
        guard shouldPush, !isRegular, navigationStack.push(route) else { return }
        sheetPath.append(route)
        sheetDetent = .medium
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
        selectedTrainID = nil
        selectedKey = nil
        deferredFocus = nil
        selectedStation = station
        push(.station(station), if: pushingPath)
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
        deferredFocus = nil
        if let train = live.train(for: key) {
            selectedStation = nil
            selectedKey = key
            selectedTrainID = train.id
            // Pushed here rather than left to `selectedTrainID`'s observer, which can't fire when
            // the id is unchanged (re-selecting the same train) and doesn't know about
            // `pushingPath` (a "back" restore must not push anything).
            push(.train(TrainSelection(key: key, liveID: train.id)), if: pushingPath)
            withAnimation(.smooth) {
                camera = cameraFocusing(train.clCoordinate, spanDegrees: 0.3)
            }
        } else if live.state.isLive || !live.trains.isEmpty {
            // No live position (yet); still open the timetable.
            selectedStation = nil
            selectedKey = key
            selectedTrainID = nil
            push(.train(TrainSelection(key: key, liveID: nil)), if: pushingPath)
        } else {
            // Live data not loaded yet; try again once positions arrive.
            deferredFocus = DeferredFocus(key: key, pushesPath: pushingPath)
        }
    }
}
