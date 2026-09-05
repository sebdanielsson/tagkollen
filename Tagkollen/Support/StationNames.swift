import Foundation
import TrafikverketKit

/// Read-only view of the cached station list for code that runs outside the app
/// (widgets, notifications) and only needs to turn signatures into names.
struct StationNames: Sendable {
    let stations: [String: TrainStation]

    static let empty = StationNames(stations: [:])

    /// Loads the cache written by `StationDirectory`. Returns `.empty` when nothing is cached yet.
    static func loadCached() -> StationNames {
        guard let data = try? Data(contentsOf: SharedStorage.stationsCacheURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(CachedStations.self, from: data) else { return .empty }
        return StationNames(stations: Dictionary(cache.stations.map { ($0.locationSignature, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Fetches the station list from the API, for widgets running before the app has cached it.
    static func fetch(using client: TrafikverketClient) async -> StationNames {
        let query = Query<TrainStation>().filter(.equal("Advertised", true)).include(TrainStation.appFields).limit(5000)
        guard let result = try? await client.fetch(query) else { return .empty }
        let live = result.objects.filter { !($0.deleted ?? false) }
        return StationNames(stations: Dictionary(live.map { ($0.locationSignature, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    var isEmpty: Bool {
        stations.isEmpty
    }

    var all: [TrainStation] {
        stations.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func station(_ signature: String?) -> TrainStation? {
        guard let signature else { return nil }
        return stations[signature]
    }

    func name(_ signature: String?) -> String {
        guard let signature else { return "–" }
        return stations[signature]?.name ?? signature
    }

    func shortName(_ signature: String?) -> String {
        guard let signature else { return "–" }
        let st = stations[signature]
        return st?.advertisedShortLocationName ?? st?.name ?? signature
    }
}

/// On-disk format of the station cache, shared with `StationDirectory`.
struct CachedStations: Codable {
    var savedAt: Date
    var stations: [TrainStation]
}
