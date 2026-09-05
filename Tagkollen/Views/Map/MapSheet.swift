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

/// The persistent bottom card on iPhone: search, saved trains, quick stations and current delays.
/// Train and station details push inside the card, like place cards in Apple Maps.
struct MapSheet: View {
    /// Type-erased so pushed screens (station boards) can append their own route types.
    @Binding var path: NavigationPath
    @Binding var detent: PresentationDetent
    var onSelectTrain: (TrainKey) -> Void

    @Environment(AppDependencies.self) private var deps
    @Environment(StationDirectory.self) private var stations
    @Environment(JourneyStore.self) private var journeyStore
    @Environment(AppSettings.self) private var settings
    @Environment(SpeechSearch.self) private var speech
    @Query(sort: \FavoriteTrain.departureDate) private var favorites: [FavoriteTrain]
    @Query(sort: \FavoriteStation.createdAt) private var favoriteStations: [FavoriteStation]

    @State private var query = ""
    @State private var date = Date.now
    @State private var journeys: [TrainJourney] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showSettings = false
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
                .navigationDestination(for: TrainKey.self) { key in
                    TrainDetailView(key: key)
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
        stationsSection
    }

    private var upcomingFavorites: [FavoriteTrain] {
        favorites.filter { fav in
            let end = fav.scheduledArrival ?? fav.departureDate.addingTimeInterval(36 * 3600)
            return end.addingTimeInterval(3 * 3600) > .now
        }
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
                VStack(spacing: 0) {
                    ForEach(Array(upcomingFavorites.prefix(4).enumerated()), id: \.element.id) { index, fav in
                        Button {
                            onSelectTrain(fav.key)
                        } label: {
                            FavoriteTrainRow(favorite: fav, journey: journeyStore.cached(fav.key))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < min(upcomingFavorites.count, 4) - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                .task(id: upcomingFavorites.map(\.id)) {
                    for fav in upcomingFavorites.prefix(4) {
                        _ = try? await journeyStore.load(fav.key)
                    }
                }
            }
        }
    }

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
        path = NavigationPath([MapSheetRoute.station(station)])
        detent = .large
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
