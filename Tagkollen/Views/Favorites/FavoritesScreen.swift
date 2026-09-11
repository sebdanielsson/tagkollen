import SwiftData
import SwiftUI
import TrafikverketKit

/// Pinned trains with live status. Regular width shows the selected train alongside.
struct FavoritesScreen: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(StationDirectory.self) private var stations
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]
    @Query(sort: \FavoriteStation.createdAt) private var favoriteStations: [FavoriteStation]

    @State private var journeys: [String: TrainJourney] = [:]
    @State private var selected: TrainKey?
    @State private var isRefreshing = false

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                list.navigationTitle("Saved")
            } detail: {
                NavigationStack {
                    if let selected {
                        TrainDetailView(key: selected)
                    } else {
                        EmptyStateView(systemImage: "star", title: "Saved trains", message: "Select a train to see its details.")
                    }
                }
            }
            // A split view that opens on an empty detail pane wastes two thirds of an iPad, so the
            // first row — the next train to leave — is selected for you, and another one is picked
            // if the one showing is deleted.
            .onChange(of: upcoming.map(\.id), initial: true) { _, ids in
                if selected == nil || !ids.contains(selected?.id ?? "") {
                    selected = upcoming.first?.key
                }
            }
        } else {
            NavigationStack {
                list
                    .navigationTitle("Saved")
                    .navigationDestination(for: TrainKey.self) { TrainDetailView(key: $0) }
                    .navigationDestination(for: TrainStation.self) { StationBoardView(station: $0) }
            }
        }
    }

    private var upcoming: [FavoriteTrain] {
        favorites.filter { !isPast($0) }.sorted { departure(of: $0) < departure(of: $1) }
    }

    private var past: [FavoriteTrain] {
        favorites.filter(isPast).sorted { departure(of: $0) < departure(of: $1) }
    }

    /// The time each row shows, so the sections read in the order the user sees. The `@Query` can
    /// only sort by `departureDate`, which `TrainKey` normalises to midnight — every run saved for
    /// the same day ties there and falls back to storage order.
    private func departure(of fav: FavoriteTrain) -> Date {
        fav.boardingTime ?? fav.scheduledDeparture ?? fav.departureDate
    }

    private func isPast(_ fav: FavoriteTrain) -> Bool {
        let end = fav.scheduledArrival ?? fav.departureDate.addingTimeInterval(36 * 3600)
        return end.addingTimeInterval(3 * 3600) < .now
    }

    private var list: some View {
        List(selection: $selected) {
            if !favoriteStations.isEmpty {
                Section("Stations") {
                    ForEach(favoriteStations) { fav in
                        if let station = stations.station(fav.signature) {
                            NavigationLink(value: station) {
                                Label(station.name, systemImage: "building.columns")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(favoriteStations[index])
                        }
                        try? modelContext.save()
                    }
                }
            }
            if favorites.isEmpty, favoriteStations.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "star",
                        title: "No saved trains",
                        message: "Tap the star on any train to keep it here. Great for a trip later this week."
                    )
                    .listRowBackground(Color.clear)
                }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { fav in row(fav) }
                        .onDelete { delete(from: upcoming, at: $0) }
                }
            }
            if !past.isEmpty {
                Section("Earlier") {
                    ForEach(past) { fav in row(fav) }
                        .onDelete { delete(from: past, at: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await refreshAll() }
        .task(id: favorites.map(\.id)) { await refreshAll() }
        .toolbar {
            if !favorites.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    @ViewBuilder
    private func row(_ fav: FavoriteTrain) -> some View {
        let journey = journeys[fav.id]
        let content = FavoriteTrainRow(favorite: fav, journey: journey)
        if sizeClass == .regular {
            content.tag(fav.key)
        } else {
            NavigationLink(value: fav.key) { content }
        }
    }

    private func delete(from source: [FavoriteTrain], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(source[index])
        }
        try? modelContext.save()
    }

    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (String, TrainJourney?).self) { group in
            for fav in favorites where !isPast(fav) || journeys[fav.id] == nil {
                let key = fav.key
                let service = deps.trains
                group.addTask { await (key.id, try? service.journey(for: key)) }
            }
            for await (id, journey) in group {
                if let journey {
                    journeys[id] = journey
                    favorites.first { $0.id == id }?.update(from: journey)
                }
            }
        }
        try? modelContext.save()
    }
}
