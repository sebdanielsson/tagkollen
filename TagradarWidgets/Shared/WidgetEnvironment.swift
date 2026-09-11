import Foundation
import SwiftData
import TrafikverketKit

/// The widget extension's slimmed-down composition root: API client, saved items and station names.
enum WidgetEnvironment {
    @MainActor private static var container: ModelContainer? = try? SharedStorage.makeModelContainer()

    /// Nil when no API key is available (neither bundled nor entered in the app).
    @MainActor static func makeClient() -> TrafikverketClient? {
        let store = APIKeyStore()
        guard store.hasKey else { return nil }
        return TrafikverketClient(keyProvider: store)
    }

    @MainActor static func savedTrains() -> [TrainSnapshot] {
        guard let container else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FavoriteTrain>(sortBy: [SortDescriptor(\.departureDate)])
        return (try? context.fetch(descriptor))?.map(TrainSnapshot.init(favorite:)) ?? []
    }

    @MainActor static func favoriteStations() -> [FavoriteStationSummary] {
        guard let container else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FavoriteStation>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor))?.map { FavoriteStationSummary(signature: $0.signature, name: $0.name) } ?? []
    }

    /// Cached station names, fetched once from the API when the app has not cached them yet.
    static func stationNames(client: TrafikverketClient?) async -> StationNames {
        let cached = StationNames.loadCached()
        if !cached.isEmpty {
            return cached
        }
        guard let client else { return .empty }
        return await StationNames.fetch(using: client)
    }

    /// Loads the journey for a saved train and merges it into the snapshot; the snapshot is returned
    /// unchanged when the request fails so the widget still has something to show.
    static func refresh(_ snapshot: TrainSnapshot, client: TrafikverketClient) async -> TrainSnapshot {
        var copy = snapshot
        if let journey = try? await TrainService(client: client).journey(for: snapshot.key) {
            copy.apply(journey)
        }
        return copy
    }
}

struct FavoriteStationSummary: Hashable, Sendable, Identifiable {
    let signature: String
    let name: String

    var id: String {
        signature
    }
}
