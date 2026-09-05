import SwiftUI
import TrafikverketKit

/// Search by train number (with a date) or by station (departure board).
struct SearchScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case train, station
        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            self == .train ? "Train number" : "Station"
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(StationDirectory.self) private var stations
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var mode: Mode = .train
    @State private var text = ""
    @State private var date = Date.now
    @State private var journeys: [TrainJourney] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var selectedStation: TrainStation?
    @State private var selectedKey: TrainKey?
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    searchList
                        .navigationTitle("Search")
                } detail: {
                    NavigationStack {
                        detail
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    searchList
                        .navigationTitle("Search")
                        .navigationDestination(for: TrainKey.self) { TrainDetailView(key: $0) }
                        .navigationDestination(for: TrainStation.self) { StationBoardView(station: $0) }
                }
            }
        }
        .onChange(of: navigation.pendingStationSignature, initial: true) { _, signature in
            guard let signature, let station = stations.station(signature) else { return }
            navigation.pendingStationSignature = nil
            selectedKey = nil
            selectedStation = station
            if sizeClass != .regular {
                path.append(station)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedKey {
            TrainDetailView(key: selectedKey)
        } else if let selectedStation {
            StationBoardView(station: selectedStation)
        } else {
            EmptyStateView(systemImage: "magnifyingglass", title: "Search", message: "Search for a train number or a station.")
        }
    }

    private var searchList: some View {
        List {
            Section {
                Picker("Search by", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if mode == .train {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, SwedishTime.timeZone)
                }
            }
            switch mode {
            case .train: trainResults
            case .station: stationResults
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $text, prompt: mode == .train ? Text("Train number, e.g. 520") : Text("Station name"))
        .keyboardType(mode == .train ? .numberPad : .default)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { Task { await searchTrains() } }
        .onChange(of: mode) { _, _ in journeys = []; error = nil }
        .onChange(of: date) { _, _ in
            if mode == .train, !text.isEmpty {
                Task { await searchTrains() }
            }
        }
        .task(id: text) {
            guard mode == .train else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await searchTrains()
        }
    }

    // MARK: Train number

    @ViewBuilder
    private var trainResults: some View {
        if isSearching {
            Section { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
        } else if let error {
            Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
        } else if !journeys.isEmpty {
            Section("Results") {
                ForEach(journeys) { journey in
                    row(for: journey)
                }
            }
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            Section {
                EmptyStateView(
                    systemImage: "train.side.front.car",
                    title: "No train found",
                    message: "No train \(text) is announced on \(Format.day(date))."
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                Text("Enter the train number from your ticket. Pick a future date to save an upcoming trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func row(for journey: TrainJourney) -> some View {
        let key = journey.key
        return Button {
            if sizeClass == .regular {
                selectedStation = nil
                selectedKey = key
            } else {
                path.append(key)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(journey.productName ?? String(localized: "Train")) \(key.ident)")
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func searchTrains() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { journeys = []; error = nil; return }
        isSearching = true
        defer { isSearching = false }
        do {
            journeys = try await deps.trains.search(ident: query, on: date)
            error = nil
        } catch {
            journeys = []
            self.error = error.localizedDescription
        }
    }

    // MARK: Station

    @ViewBuilder
    private var stationResults: some View {
        let matches = stations.search(text)
        if !stations.isLoaded {
            Section { HStack { Spacer(); ProgressView("Loading stations…"); Spacer() }.listRowBackground(Color.clear) }
        } else if text.isEmpty {
            Section("Major stations") {
                ForEach(majorStations) { stationRow($0) }
            }
        } else if matches.isEmpty {
            Section { Text("No station matches \(text).").foregroundStyle(.secondary) }
        } else {
            Section("Stations") {
                ForEach(matches) { stationRow($0) }
            }
        }
    }

    private var majorStations: [TrainStation] {
        ["Cst", "G", "M", "U", "Lp", "Nr", "Vå", "Öb", "Hb", "Lu", "Gä", "Sk", "Jö", "Ck", "Suc", "Umå", "Lå"]
            .compactMap { stations.station($0) }
    }

    private func stationRow(_ station: TrainStation) -> some View {
        Button {
            if sizeClass == .regular {
                selectedKey = nil
                selectedStation = station
            } else {
                path.append(station)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).font(.body)
                    Text(station.locationSignature).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).imageScale(.small)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
