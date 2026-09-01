import SwiftData
import SwiftUI

/// Pinned trains with live status. Regular width shows the selected train alongside.
struct FavoritesScreen: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(StationDirectory.self) private var stations
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]

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
        } else {
            NavigationStack {
                list
                    .navigationTitle("Saved")
                    .navigationDestination(for: TrainKey.self) { TrainDetailView(key: $0) }
            }
        }
    }

    private var upcoming: [FavoriteTrain] {
        favorites.filter { !isPast($0) }
    }

    private var past: [FavoriteTrain] {
        favorites.filter(isPast)
    }

    private func isPast(_ fav: FavoriteTrain) -> Bool {
        let end = fav.scheduledArrival ?? fav.departureDate.addingTimeInterval(36 * 3600)
        return end.addingTimeInterval(3 * 3600) < .now
    }

    private var list: some View {
        List(selection: $selected) {
            if favorites.isEmpty {
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
        let content = FavoriteRow(favorite: fav, journey: journey)
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

private struct FavoriteRow: View {
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
