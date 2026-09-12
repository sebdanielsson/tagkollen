import SwiftData
import SwiftUI

/// The trains card at the top of the map sheet: the runs the user kept, and — in a second tab —
/// the ones they last opened. Both tabs render the same kind of row on purpose, so switching
/// between them is a change of source, not of reading.
struct MapTrainsCard: View {
    var onSelectTrain: (TrainKey) -> Void

    /// What the card is showing: what the user kept, or what they last looked at.
    enum Tab: String, CaseIterable, Identifiable {
        case saved, recent
        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            self == .saved ? "Saved" : "Recent"
        }
    }

    @Environment(JourneyStore.self) private var journeyStore
    @Environment(AppSettings.self) private var settings
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]
    /// Nil until the user picks a tab, so the card can open on whichever one has something to show.
    @State private var tab: Tab?

    private static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recents.isEmpty {
                Text("Saved trains")
                    .font(.title3.weight(.semibold))
            } else {
                Picker("Trains", selection: Binding(get: { visibleTab }, set: { tab = $0 })) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch visibleTab {
            case .saved: savedCard
            case .recent: recentCard
            }
        }
    }

    /// Sorted by the time each row shows, not by the `@Query`'s `departureDate` — `TrainKey`
    /// normalises that to midnight, so runs saved for the same day tie and fall back to storage
    /// order, which here would also decide which four make the cut.
    private var upcomingFavorites: [FavoriteTrain] {
        favorites.filter { fav in
            let end = fav.scheduledArrival ?? fav.departureDate.addingTimeInterval(36 * 3600)
            return end.addingTimeInterval(3 * 3600) > .now
        }
        .map { ($0, departure(of: $0)) }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// Read from the same snapshot `FavoriteTrainRow` renders, so a trip segment sorts by its
    /// boarding stop and a freshly pinned run takes its place as soon as its journey is cached.
    private func departure(of fav: FavoriteTrain) -> Date {
        var snapshot = TrainSnapshot(favorite: fav)
        if let journey = journeyStore.cached(fav.key) {
            snapshot.apply(journey)
        }
        return snapshot.scheduledDeparture ?? fav.departureDate
    }

    /// Runs the user opened but never pinned. Saved ones are filtered out — they are one tap away
    /// in the other tab, and the same train twice on one screen reads like a bug.
    private var recents: [RecentTrain] {
        let saved = Set(favorites.map(\.id))
        return settings.recentTrains.filter { !saved.contains($0.id) }
    }

    /// Saved until the user says otherwise, except when there is nothing saved to show: the star
    /// hint earns its space only while it is the card's whole purpose.
    private var visibleTab: Tab {
        tab ?? (upcomingFavorites.isEmpty && !recents.isEmpty ? .recent : .saved)
    }

    private var recentCard: some View {
        rows(recents) { recent in
            RecentTrainRow(recent: recent, journey: journeyStore.cached(recent.key))
        } select: {
            onSelectTrain($0.key)
        }
        .task(id: recents.map(\.id)) {
            for recent in recents.prefix(Self.maxRows) {
                _ = try? await journeyStore.load(recent.key)
            }
        }
    }

    @ViewBuilder
    private var savedCard: some View {
        if upcomingFavorites.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "star")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                Text("Tap the star on a train to keep it here. Handy for a trip later this week.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        } else {
            rows(upcomingFavorites) { fav in
                FavoriteTrainRow(favorite: fav, journey: journeyStore.cached(fav.key))
            } select: {
                onSelectTrain($0.key)
            }
            .task(id: upcomingFavorites.map(\.id)) {
                for fav in upcomingFavorites.prefix(Self.maxRows) {
                    _ = try? await journeyStore.load(fav.key)
                }
            }
        }
    }

    /// The shared body of both tabs: up to four tappable rows, divided, on one rounded card.
    private func rows<Item: Identifiable>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View,
        select: @escaping (Item) -> Void
    ) -> some View {
        let shown = Array(items.prefix(Self.maxRows))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                Button {
                    select(item)
                } label: {
                    row(item)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < shown.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }
}
