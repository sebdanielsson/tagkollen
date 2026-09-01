import MapKit
import SwiftData
import SwiftUI
import TrafikverketKit

/// Everything about one train run: header, live position, every stop with planned /
/// estimated / actual times, deviations and traffic messages.
struct TrainDetailView: View {
    let key: TrainKey?
    var liveID: String?
    var onClose: (() -> Void)?

    @Environment(AppDependencies.self) private var deps
    @Environment(JourneyStore.self) private var journeyStore
    @Environment(LiveTrainStore.self) private var live
    @Environment(StationDirectory.self) private var stations
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [FavoriteTrain]

    @State private var journey: TrainJourney?
    @State private var messages: [TrainMessage] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var refreshTask: Task<Void, Never>?

    private var liveTrain: LiveTrain? {
        if let liveID, let t = live.train(id: liveID) {
            return t
        }
        if let key {
            return live.train(for: key)
        }
        return nil
    }

    private var effectiveKey: TrainKey? {
        key ?? liveTrain?.key
    }

    private var favorite: FavoriteTrain? {
        guard let id = effectiveKey?.id else { return nil }
        return favorites.first { $0.id == id }
    }

    var body: some View {
        List {
            if let journey {
                JourneyHeaderSection(journey: journey, liveTrain: liveTrain)
                if let liveTrain {
                    Section {
                        LivePositionCard(train: liveTrain, journey: journey)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if !messages.isEmpty {
                    Section("Traffic messages") {
                        ForEach(messages) { MessageCard(message: $0) }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                Section {
                    StopTimelineView(journey: journey)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    HStack {
                        Text("Stops")
                        Spacer()
                        Text("\(journey.stops.count) stations")
                            .textCase(nil)
                    }
                }
                JourneyFactsSection(journey: journey)
            } else if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else if let liveTrain, effectiveKey == nil {
                Section {
                    LivePositionCard(train: liveTrain, journey: nil)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Section {
                    EmptyStateView(
                        systemImage: "shippingbox",
                        title: "No timetable",
                        message: """
                        This train is not advertised for passengers, so Trafikverket publishes no stops for it. \
                        It is most likely a freight or service train.
                        """
                    )
                    .listRowBackground(Color.clear)
                }
            } else if let error {
                Section {
                    EmptyStateView(
                        systemImage: "wifi.exclamationmark",
                        title: "Could not load",
                        message: LocalizedStringKey(error),
                        actionTitle: "Try again"
                    ) { Task { await load() } }
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    EmptyStateView(
                        systemImage: "calendar.badge.exclamationmark",
                        title: "No timetable found",
                        message: "Trafikverket has no announcements for this train on the selected day."
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: onClose)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if effectiveKey != nil {
                    Button(favorite == nil ? "Save" : "Saved", systemImage: favorite == nil ? "star" : "star.fill") {
                        toggleFavorite()
                    }
                    .tint(favorite == nil ? nil : .yellow)
                    .sensoryFeedback(.success, trigger: favorite != nil)
                }
                if liveTrain != nil, onClose == nil {
                    Button("Show on map", systemImage: "map") {
                        if let effectiveKey {
                            navigation.showOnMap(effectiveKey)
                        }
                    }
                }
                if let journey {
                    ShareLink(item: shareText(for: journey)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .refreshable { await load() }
        .task(id: effectiveKey?.id) {
            await load()
            await autoRefresh()
        }
    }

    private var title: String {
        if let key = effectiveKey {
            return String(localized: "Train \(key.ident)")
        }
        if let liveTrain {
            return String(localized: "Train \(liveTrain.displayNumber)")
        }
        return String(localized: "Train")
    }

    // MARK: Loading

    private func load() async {
        guard let key = effectiveKey else { return }
        if journey == nil {
            journey = journeyStore.cached(key)
            isLoading = journey == nil
        }
        defer { isLoading = false }
        do {
            let loaded = try await journeyStore.load(key, force: journey != nil)
            journey = loaded
            error = nil
            if let loaded {
                favorite?.update(from: loaded)
                let related = try? await deps.trains.messages(affecting: loaded.allSignatures)
                messages = related ?? []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func autoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if journey?.status != .arrived {
                await load()
            }
        }
    }

    // MARK: Favorites

    private func toggleFavorite() {
        guard let key = effectiveKey else { return }
        if let favorite {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteTrain(key: key, journey: journey))
        }
        try? modelContext.save()
    }

    private func shareText(for journey: TrainJourney) -> String {
        var lines: [String] = []
        let product = journey.productName ?? String(localized: "Train")
        lines.append("\(product) \(journey.key.ident) · \(Format.day(journey.key.departureDate))")
        if let o = journey.origin, let d = journey.destination {
            lines.append("\(stations.name(o.signature)) \(Format.clock(o.departure?.advertisedTimeAtLocation)) → "
                + "\(stations.name(d.signature)) \(Format.clock(d.arrival?.advertisedTimeAtLocation))")
        }
        if let delay = Format.delay(journey.currentDelay) {
            lines.append(delay)
        }
        lines.append("tagkollen://train/\(journey.key.id)")
        return lines.joined(separator: "\n")
    }
}
