import SwiftData
import SwiftUI
import TrafikverketKit

/// What the map card is showing on top of its search root.
enum MapSheetRoute: Hashable {
    case train(TrainSelection)
    case station(TrainStation)
}

struct TrainSelection: Hashable {
    var key: TrainKey?
    var liveID: String?
}

/// Search, saved trains and quick stations. The persistent bottom card on iPhone, where train and
/// station details push inside it like place cards in Apple Maps; the sidebar on iPad, where the
/// details open in an inspector instead and the saved list has room to show every upcoming train.
struct MapSheet: View {
    /// Where the sheet is being shown. Decided by `MapScreen`, not read from the size class: a
    /// `NavigationSplitView` sidebar column is compact width whatever the device, so the
    /// environment would call the iPad sidebar a phone card.
    enum Style {
        /// The bottom card on iPhone: room for the next few saved trains and a strip of stations.
        case card
        /// The iPad sidebar: every upcoming saved train and a full station list.
        case sidebar
    }

    var style: Style = .card
    /// Owned by `MapScreen`, which mirrors it in a typed shadow (`MapNavigationStack`) so a pop
    /// can restore the map. Nothing inside this stack may append to it directly — every push has
    /// to go through `MapScreen`, or the shadow silently drifts and misdirects the next "back".
    @Binding var path: NavigationPath
    @Binding var detent: PresentationDetent
    var onSelectTrain: (TrainKey) -> Void
    var onSelectStation: (TrainStation) -> Void

    @Environment(AppDependencies.self) private var deps
    @Environment(StationDirectory.self) private var stations
    @Environment(JourneyStore.self) private var journeyStore
    @Environment(AppSettings.self) private var settings
    @Environment(SpeechSearch.self) private var speech
    @Environment(TrainMonitor.self) private var monitor
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]
    @Query(sort: \FavoriteStation.createdAt) private var favoriteStations: [FavoriteStation]

    @State private var query = ""
    @State private var date = Date.now
    @State private var journeys: [TrainJourney] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showSettings = false
    @State private var showEarlier = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            root
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: MapSheetRoute.self) { route in
                    switch route {
                    case let .train(selection):
                        TrainDetailView(key: selection.key, liveID: selection.liveID)
                    case let .station(station):
                        StationBoardView(station: station, onSelectTrain: onSelectTrain)
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused {
                detent = .large
            }
        }
        .onChange(of: speech.transcript) { _, text in
            guard speech.isListening || !text.isEmpty else { return }
            query = text
            if !text.isEmpty {
                detent = .large
            }
        }
        .onChange(of: speech.errorMessage) { _, message in
            if let message {
                searchError = message
            }
        }
        .task(id: query) {
            guard !query.isEmpty else {
                journeys = []
                searchError = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await searchTrains()
        }
        .onChange(of: date) { _, _ in Task { await searchTrains() } }
    }

    // MARK: Root

    private var root: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if query.isEmpty {
                    idleContent
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, MapScreen.sheetTopPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Train number or station", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { Task { await searchTrains() } }
                if !query.isEmpty, !speech.isListening {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
                Button {
                    searchFocused = false
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                        .foregroundStyle(speech.isListening ? Color.red : Color.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(speech.isListening ? "Stop listening" : "Search by voice"))
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.fill.tertiary, in: .capsule)
            .onTapGesture { searchFocused = true }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Settings"))
        }
    }

    // MARK: Idle content

    @ViewBuilder
    private var idleContent: some View {
        savedTrainsSection
        if style == .sidebar, !pastFavorites.isEmpty {
            earlierSection
        }
        stationsSection
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

    /// Runs that have already arrived. The card has no room for them; the sidebar keeps them so a
    /// train saved for a trip that is over can still be found and removed, which is otherwise only
    /// possible by searching the run up again and un-starring it from its detail.
    private var pastFavorites: [FavoriteTrain] {
        favorites.filter { fav in
            let end = fav.scheduledArrival ?? fav.departureDate.addingTimeInterval(36 * 3600)
            return end.addingTimeInterval(3 * 3600) <= .now
        }
        .map { ($0, departure(of: $0)) }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    /// The card only has room for the next few; the sidebar shows them all.
    private var shownFavorites: [FavoriteTrain] {
        let upcoming = upcomingFavorites
        return style == .sidebar ? upcoming : Array(upcoming.prefix(4))
    }

    private var savedTrainsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved trains")
                .font(.title3.weight(.semibold))
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
                rows(for: shownFavorites)
                    .task(id: shownFavorites.map(\.id)) {
                        for fav in shownFavorites {
                            _ = try? await journeyStore.load(fav.key)
                        }
                    }
            }
        }
    }

    /// Saved runs that have already arrived, so they can still be removed. Collapsed by default:
    /// they are history, not something to act on.
    private var earlierSection: some View {
        DisclosureGroup(isExpanded: $showEarlier) {
            rows(for: pastFavorites)
                .padding(.top, 10)
        } label: {
            Text("Earlier")
                .font(.title3.weight(.semibold))
        }
        .tint(.primary)
    }

    /// One tappable row per saved run, each removable from a long press.
    private func rows(for trains: [FavoriteTrain]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(trains.enumerated()), id: \.element.id) { index, fav in
                Button {
                    onSelectTrain(fav.key)
                } label: {
                    FavoriteTrainRow(favorite: fav, journey: journeyStore.cached(fav.key))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove", systemImage: "star.slash", role: .destructive) {
                        remove(fav)
                    }
                }
                if index < trains.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    /// Unsaves a run. Goes through `TrainMonitor` for the same reason the star in `TrainDetailView`
    /// does: a pending "departs soon" reminder has to be cancelled and the widget timelines
    /// reloaded, or a train the user just removed still notifies them and still shows in a widget.
    private func remove(_ fav: FavoriteTrain) {
        let id = fav.id
        modelContext.delete(fav)
        try? modelContext.save()
        monitor.trainRemoved(id)
    }

    // MARK: Search results

    private var looksLikeTrainNumber: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
    }

    @ViewBuilder
    private var searchResults: some View {
        if looksLikeTrainNumber {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Trains")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.timeZone, SwedishTime.timeZone)
                }
                if isSearching, journeys.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else if let searchError {
                    Label(searchError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if journeys.isEmpty {
                    Text("No train \(query.trimmingCharacters(in: .whitespaces)) is announced on \(Format.day(date)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(journeys.enumerated()), id: \.element.id) { index, journey in
                            Button {
                                searchFocused = false
                                onSelectTrain(journey.key)
                            } label: {
                                journeyRow(journey)
                            }
                            .buttonStyle(.plain)
                            if index < journeys.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                }
            }
        }

        let matches = stations.search(query, limit: 20)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stations")
                    .font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, station in
                        Button {
                            open(station)
                        } label: {
                            HStack {
                                Image(systemName: "building.columns")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                    Text(station.locationSignature).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary).imageScale(.small)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < matches.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
            }
        } else if !looksLikeTrainNumber {
            Text("No station matches \(query).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func journeyRow(_ journey: TrainJourney) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(journey.productName ?? String(localized: "Train")) \(journey.key.ident)")
                    .font(.headline)
                Text("\(stations.name(journey.origin?.signature)) → \(stations.name(journey.destination?.signature))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(Format.clock(journey.scheduledDeparture)) – \(Format.clock(journey.scheduledArrival))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DelayBadge(delay: journey.currentDelay, canceled: journey.isFullyCanceled)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).imageScale(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    // MARK: Actions

    private func open(_ station: TrainStation) {
        searchFocused = false
        onSelectStation(station)
    }

    private func searchTrains() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard looksLikeTrainNumber else {
            journeys = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            journeys = try await deps.trains.search(ident: trimmed, on: date)
            searchError = nil
        } catch {
            journeys = []
            searchError = error.localizedDescription
        }
    }
}

// MARK: - Stations

extension MapSheet {
    private enum QuickStationKind {
        case favorite, recent, major

        var symbol: String {
            switch self {
            case .favorite: "star.fill"
            case .recent: "clock.arrow.circlepath"
            case .major: "building.columns.fill"
            }
        }

        var tint: Color {
            self == .favorite ? .yellow : .accentColor
        }
    }

    private struct QuickStation: Identifiable {
        let station: TrainStation
        let kind: QuickStationKind
        var id: String {
            station.id
        }
    }

    /// Starred stations first, then recently opened ones, then the big hubs.
    private var quickStations: [QuickStation] {
        let majors = ["Cst", "G", "M", "U", "Lp", "Nr", "Vå", "Öb", "Hb", "Lu", "Gä", "Suc", "Umå"]
        var seen = Set<String>()
        let ordered: [(String, QuickStationKind)] = favoriteStations.map { ($0.signature, .favorite) }
            + settings.recentStations.map { ($0, .recent) }
            + majors.map { ($0, .major) }
        return ordered
            .filter { seen.insert($0.0).inserted }
            .compactMap { sig, kind in stations.station(sig).map { QuickStation(station: $0, kind: kind) } }
            .prefix(14)
            .map(\.self)
    }

    private var stationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stations")
                .font(.title3.weight(.semibold))
            if style == .sidebar {
                stationList
            } else {
                stationStrip
            }
        }
    }

    /// The sidebar has the height for a proper list: full names, and the icon says why a station
    /// is here (starred, recent, or simply a big one).
    private var stationList: some View {
        let items = quickStations
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    open(item.station)
                } label: {
                    HStack {
                        Image(systemName: item.kind.symbol)
                            .foregroundStyle(item.kind.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.station.name)
                            Text(item.station.locationSignature).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary).imageScale(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < items.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    /// The card's compact take: a row of circles to swipe through.
    private var stationStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(quickStations) { item in
                    let station = item.station
                    Button {
                        open(station)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.kind.symbol)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(item.kind.tint.gradient, in: .circle)
                            Text(station.advertisedShortLocationName ?? station.name)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
}
