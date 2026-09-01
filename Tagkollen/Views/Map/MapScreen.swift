import MapKit
import SwiftUI
import TrafikverketKit

/// The live map. Full-bleed map with glass controls; the selected train opens in a sheet
/// (compact width) or an inspector panel (regular width, e.g. iPad).
struct MapScreen: View {
    @Environment(LiveTrainStore.self) private var live
    @Environment(DelayIndex.self) private var delays
    @Environment(AppSettings.self) private var settings
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var camera: MapCameraPosition = .region(MapScreen.swedenRegion)
    @State private var visibleRegion: MKCoordinateRegion = MapScreen.swedenRegion
    @State private var selectedTrainID: String?
    @State private var selectedKey: TrainKey?
    @State private var showSettings = false
    @State private var followSelection = false

    static let swedenRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 14.5, longitudeDelta: 14.5)
    )

    private var isRegular: Bool {
        sizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            TrainMapView(
                camera: $camera,
                visibleRegion: $visibleRegion,
                selectedTrainID: $selectedTrainID,
                selectedKey: selectedKey
            )
            .ignoresSafeArea(edges: isRegular ? [] : .all)
            .safeAreaInset(edge: .top, spacing: 0) { topOverlay }
            .navigationTitle("Map")
            .toolbar(isRegular ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if isRegular {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .inspector(isPresented: inspectorBinding) {
                if isRegular, let selection = currentSelection {
                    NavigationStack {
                        TrainDetailView(key: selection.key, liveID: selection.liveID, onClose: clearSelection)
                    }
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
                }
            }
            .sheet(isPresented: sheetBinding) {
                if let selection = currentSelection {
                    NavigationStack {
                        TrainDetailView(key: selection.key, liveID: selection.liveID, onClose: clearSelection)
                    }
                    .presentationDetents([.fraction(0.4), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .onChange(of: selectedTrainID) { _, id in
            if let id, let train = live.train(id: id) {
                selectedKey = train.key
                if followSelection || isRegular {
                    withAnimation(.smooth) { camera = .camera(MapCamera(centerCoordinate: train.clCoordinate, distance: 60000)) }
                }
            }
        }
        .onChange(of: navigation.pendingMapFocus) { _, key in
            guard let key else { return }
            focus(on: key)
        }
        .onChange(of: live.updateCount) { _, _ in
            if navigation.pendingMapFocus != nil, let key = navigation.pendingMapFocus {
                focus(on: key)
            }
        }
    }

    // MARK: Selection plumbing

    private struct Selection {
        var key: TrainKey?
        var liveID: String?
    }

    private var currentSelection: Selection? {
        if selectedTrainID == nil, selectedKey == nil {
            return nil
        }
        return Selection(key: selectedKey, liveID: selectedTrainID)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { isRegular && currentSelection != nil }, set: {
            if !$0 {
                clearSelection()
            }
        })
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { !isRegular && currentSelection != nil }, set: {
            if !$0 {
                clearSelection()
            }
        })
    }

    private func clearSelection() {
        selectedTrainID = nil
        selectedKey = nil
    }

    private func focus(on key: TrainKey) {
        if let train = live.train(for: key) {
            navigation.pendingMapFocus = nil
            selectedKey = key
            selectedTrainID = train.id
            withAnimation(.smooth) {
                camera = .camera(MapCamera(centerCoordinate: train.clCoordinate, distance: 40000))
            }
        } else if live.state.isLive {
            // Train has no live position yet; still open its timetable.
            navigation.pendingMapFocus = nil
            selectedKey = key
            selectedTrainID = nil
        }
    }

    // MARK: Overlay

    private var topOverlay: some View {
        HStack(alignment: .top) {
            StatusPill(state: live.state, count: live.trains.count, lastUpdate: live.lastUpdate)
            Spacer()
            if !isRegular {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                            .buttonStyle(.glass)
                            .labelStyle(.iconOnly)
                        Button("Whole country", systemImage: "arrow.down.left.and.arrow.up.right") {
                            withAnimation(.smooth) { camera = .region(Self.swedenRegion) }
                        }
                        .buttonStyle(.glass)
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, isRegular ? 8 : 4)
        .padding(.bottom, 8)
    }
}
