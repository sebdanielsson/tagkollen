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
    @Environment(TrainMonitor.self) private var monitor
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]
    /// The card always opens on Saved. Resolving a default from the lists instead looked tidier
    /// but latched: the picker writes its selection back, so one render before `@Query` had
    /// delivered the favorites was enough to leave the card stuck on Recent.
    @State private var tab: Tab = .saved

    private static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recents.isEmpty {
                Text("Saved trains")
                    .font(.title3.weight(.semibold))
            } else {
                Picker("Trains", selection: $tab) {
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

    /// Everything the user opened, saved or not. A saved run still belongs here — it is part of
    /// what you were just looking at — and its star says which it is without a trip to the tab.
    private var recents: [RecentTrain] {
        settings.recentTrains
    }

    private func favorite(for recent: RecentTrain) -> FavoriteTrain? {
        favorites.first { $0.id == recent.id }
    }

    /// Falls back to Saved when the other tab has nothing left to show — a run can drop out of
    /// Recent while the user is looking at it, and an empty grey card is not an answer.
    private var visibleTab: Tab {
        recents.isEmpty ? .saved : tab
    }

    private var recentCard: some View {
        rows(recents) { recent in
            RecentTrainRow(recent: recent, journey: journeyStore.cached(recent.key))
        } select: {
            onSelectTrain($0.key)
        } accessory: { recent in
            saveButton(for: recent)
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
            } accessory: { _ in
                EmptyView()
            }
            .task(id: upcomingFavorites.map(\.id)) {
                for fav in upcomingFavorites.prefix(Self.maxRows) {
                    _ = try? await journeyStore.load(fav.key)
                }
            }
        }
    }

    /// Says whether the run is saved, and saves or unsaves it without leaving the card.
    private func saveButton(for recent: RecentTrain) -> some View {
        let saved = favorite(for: recent) != nil
        return Button {
            toggleSaved(recent)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.subheadline)
                .foregroundStyle(saved ? Color.yellow : Color.secondary)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(saved ? "Saved" : "Save"))
        .sensoryFeedback(.success, trigger: saved)
    }

    /// Mirrors the star in `TrainDetailView`: the same reminders and widget refresh have to follow,
    /// or a train saved from here would be one the monitor never looks at.
    private func toggleSaved(_ recent: RecentTrain) {
        if let existing = favorite(for: recent) {
            let id = existing.id
            modelContext.delete(existing)
            try? modelContext.save()
            monitor.trainRemoved(id)
        } else {
            let journey = journeyStore.cached(recent.key)
            let fav = FavoriteTrain(key: recent.key, journey: journey)
            recent.fillIn(fav)
            modelContext.insert(fav)
            try? modelContext.save()
            monitor.trainSaved(fav, journey: journey)
        }
    }

    /// The shared body of both tabs: up to four tappable rows, divided, on one rounded card.
    /// The accessory sits beside the row's button rather than inside its label — a button nested
    /// in another button's label never sees the tap.
    private func rows<Item: Identifiable>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View,
        select: @escaping (Item) -> Void,
        @ViewBuilder accessory: @escaping (Item) -> some View
    ) -> some View {
        let shown = Array(items.prefix(Self.maxRows))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 0) {
                    Button {
                        select(item)
                    } label: {
                        row(item)
                            .padding(.leading, 14)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    accessory(item)
                }
                .padding(.trailing, 14)
                if index < shown.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }
}
