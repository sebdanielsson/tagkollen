import MapKit
import os
import SwiftUI
import TrafikverketKit

/// The live map. On iPhone it is Apple Maps-like: full-bleed map, glass controls bottom-right and a
/// persistent bottom card for search, saved trains and details. On iPad the detail opens in an inspector.
struct MapScreen: View {
    @Environment(LiveTrainStore.self) private var live
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var camera: MapCameraPosition = .region(MapScreen.swedenRegion)
    @State private var visibleRegion: MKCoordinateRegion = MapScreen.swedenRegion
    @State private var selectedTrainID: String?
    @State private var selectedKey: TrainKey?
    @State private var showSettings = false
    @State private var sheetPath = NavigationPath()
    @State private var sheetDetent: PresentationDetent = .height(MapScreen.collapsedSheetHeight)
    @State private var sheetPresented = true
    @Namespace private var mapScope

    static let swedenRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 14.5, longitudeDelta: 14.5)
    )

    /// Height of the collapsed card: the search field with breathing room under the grabber.
    static let collapsedSheetHeight: CGFloat = 70
    static let sheetTopPadding: CGFloat = 16
    private static let logger = Logger(subsystem: "se.sebastiandanielsson.tagkollen", category: "MapScreen")

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
            selectedKey = train.key
            if !isRegular {
                sheetPath = NavigationPath([MapSheetRoute.train(TrainSelection(key: train.key, liveID: id))])
                sheetDetent = .medium
            }
            withAnimation(.smooth) { camera = .camera(MapCamera(centerCoordinate: train.clCoordinate, distance: 60000)) }
        }
        .onChange(of: navigation.pendingMapFocus) { _, key in
            guard let key else { return }
            focus(on: key)
        }
        .onChange(of: live.updateCount) { _, _ in
            if let key = navigation.pendingMapFocus {
                focus(on: key)
            }
        }
        .onChange(of: sheetPath) { _, path in
            Self.logger.debug("sheetPath → \(path.count) items")
            // Popping the card back to search clears the map selection.
            if path.isEmpty, selectedTrainID != nil || selectedKey != nil {
                selectedTrainID = nil
                selectedKey = nil
            }
        }
    }

    private var map: some View {
        TrainMapView(
            camera: $camera,
            visibleRegion: $visibleRegion,
            selectedTrainID: $selectedTrainID,
            selectedKey: selectedKey,
            scope: mapScope
        )
    }

    // MARK: iPhone

    private var compactLayout: some View {
        map
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    StatusPill(state: live.state, count: live.trains.count, lastUpdate: live.lastUpdate)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .bottomTrailing) {
                MapControlsCluster(camera: $camera, scope: mapScope)
                    .padding(.trailing, 12)
                    .padding(.bottom, Self.collapsedSheetHeight + 16)
            }
            .mapScope(mapScope)
            .sheet(isPresented: $sheetPresented) {
                MapSheet(path: $sheetPath, detent: $sheetDetent, onSelectTrain: select)
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
            StatusPill(state: live.state, count: live.trains.count, lastUpdate: live.lastUpdate)
            Spacer()
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .buttonStyle(.glass)
                        .labelStyle(.iconOnly)
                    MapUserLocationButton(scope: mapScope)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                    Button("Whole country", systemImage: "arrow.down.left.and.arrow.up.right") {
                        withAnimation(.smooth) { camera = .region(Self.swedenRegion) }
                    }
                    .buttonStyle(.glass)
                    .labelStyle(.iconOnly)
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
        if !isRegular {
            sheetPath = NavigationPath()
        }
    }

    /// Selects a train from a list or search result: zooms to it when it has a live position.
    private func select(_ key: TrainKey) {
        focus(on: key)
    }

    private func focus(on key: TrainKey) {
        navigation.pendingMapFocus = nil
        if let train = live.train(for: key) {
            selectedKey = key
            selectedTrainID = train.id
            withAnimation(.smooth) {
                camera = .camera(MapCamera(centerCoordinate: train.clCoordinate, distance: 40000))
            }
        } else if live.state.isLive || !live.trains.isEmpty {
            // No live position (yet); still open the timetable.
            selectedKey = key
            selectedTrainID = nil
            if !isRegular {
                sheetPath = NavigationPath([MapSheetRoute.train(TrainSelection(key: key, liveID: nil))])
                sheetDetent = .medium
            }
        } else {
            // Live data not loaded yet; try again once positions arrive.
            navigation.pendingMapFocus = key
        }
    }
}
