import SwiftData
import SwiftUI
import TrafikverketKit

/// Departure / arrival board for one station.
struct StationBoardView: View {
    let station: TrainStation
    /// When set (the map card on iPhone), selecting a train goes through this instead of a plain
    /// push, so the map behind can update too. `nil` falls back to a normal navigation push — used
    /// where there's no map to update (the Search and Saved tabs on iPad).
    var onSelectTrain: ((TrainKey) -> Void)?

    enum Board: String, CaseIterable, Identifiable {
        case departures, arrivals
        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            self == .departures ? "Departures" : "Arrivals"
        }
    }

    @Environment(AppDependencies.self) private var deps
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var favoriteStations: [FavoriteStation]
    @State private var board: Board = .departures
    @State private var rows: [TrainAnnouncement] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selected: TrainKey?

    var body: some View {
        List {
            Section {
                Picker("Board", selection: $board) {
                    ForEach(Board.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let markdown = station.informationMarkdown {
                Section {
                    Label {
                        Text(Self.attributed(markdown))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                if isLoading, rows.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    let kind = board == .departures ? String(localized: "departures") : String(localized: "arrivals")
                    Text("No \(kind) in the next six hours.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        if let onSelectTrain {
                            Button { onSelectTrain(key(for: row)) } label: {
                                AnnouncementRow(announcement: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: key(for: row)) {
                                AnnouncementRow(announcement: row)
                            }
                        }
                    }
                }
            } header: {
                Text("Next six hours")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isFavorite ? "Saved" : "Save", systemImage: isFavorite ? "star.fill" : "star") {
                    toggleFavorite()
                }
                .tint(isFavorite ? .yellow : nil)
                .sensoryFeedback(.success, trigger: isFavorite)
            }
        }
        .navigationDestination(for: TrainKey.self) { TrainDetailView(key: $0) }
        .refreshable { await load() }
        .task(id: board) { await load() }
        .onAppear { settings.addRecentStation(station.locationSignature) }
    }

    /// Renders the sanitised station text with tappable links.
    private static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown.strippingHTML)
    }

    private var isFavorite: Bool {
        favoriteStations.contains { $0.signature == station.locationSignature }
    }

    private func toggleFavorite() {
        if let existing = favoriteStations.first(where: { $0.signature == station.locationSignature }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteStation(signature: station.locationSignature, name: station.name))
        }
        try? modelContext.save()
    }

    private func key(for row: TrainAnnouncement) -> TrainKey {
        TrainKey(ident: row.advertisedTrainIdent ?? "", departureDate: row.scheduledDepartureDateTime ?? .now)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let start = Date.now.addingTimeInterval(-10 * 60)
            rows = switch board {
            case .departures: try await deps.trains.departures(from: station.locationSignature, start: start)
            case .arrivals: try await deps.trains.arrivals(to: station.locationSignature, start: start)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
