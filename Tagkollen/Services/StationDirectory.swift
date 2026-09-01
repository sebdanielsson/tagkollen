import Foundation
import os
import TrafikverketKit

/// All advertised stations, cached on disk and refreshed weekly. Used to turn signatures
/// like `Cst` into "Stockholm Central" and to search stations by name.
@MainActor
@Observable
final class StationDirectory {
    private(set) var stationsBySignature: [String: TrainStation] = [:]
    private(set) var all: [TrainStation] = []
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?
    private(set) var error: String?

    private let client: TrafikverketClient
    private let logger = Logger(subsystem: "se.sebastiandanielsson.tagkollen", category: "Stations")
    private static let maxCacheAge: TimeInterval = 7 * 24 * 3600

    init(client: TrafikverketClient) {
        self.client = client
    }

    var isLoaded: Bool {
        !all.isEmpty
    }

    func station(_ signature: String) -> TrainStation? {
        stationsBySignature[signature]
    }

    func name(_ signature: String?) -> String {
        guard let signature else { return "–" }
        return stationsBySignature[signature]?.name ?? signature
    }

    func shortName(_ signature: String?) -> String {
        guard let signature else { return "–" }
        let st = stationsBySignature[signature]
        return st?.advertisedShortLocationName ?? st?.name ?? signature
    }

    /// Case- and diacritic-insensitive prefix/word search on name and signature.
    func search(_ text: String, limit: Int = 40) -> [TrainStation] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let folded = needle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var exact: [TrainStation] = []
        var prefix: [TrainStation] = []
        var contains: [TrainStation] = []
        for st in all {
            let name = st.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let sig = st.locationSignature.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if sig == folded || name == folded {
                exact.append(st)
            } else if name.hasPrefix(folded) || name.split(separator: " ").contains(where: { $0.hasPrefix(folded) }) {
                prefix.append(st)
            } else if name.contains(folded) {
                contains.append(st)
            }
            if exact.count + prefix.count + contains.count > limit * 3 {
                break
            }
        }
        return Array((exact + prefix + contains).prefix(limit))
    }

    // MARK: Loading

    func load() async {
        if let cached = Self.readCache() {
            apply(cached.stations)
            lastRefresh = cached.savedAt
        }
        let stale = lastRefresh.map { Date.now.timeIntervalSince($0) > Self.maxCacheAge } ?? true
        if all.isEmpty || stale {
            await refresh()
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = Query<TrainStation>()
                .filter(.equal("Advertised", true))
                .include(TrainStation.appFields)
                .limit(5000)
            let result = try await client.fetch(query)
            let live = result.objects.filter { !($0.deleted ?? false) }
            guard !live.isEmpty else { return }
            apply(live)
            lastRefresh = .now
            error = nil
            Self.writeCache(live)
        } catch {
            self.error = error.localizedDescription
            logger.error("Station refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ stations: [TrainStation]) {
        stationsBySignature = Dictionary(stations.map { ($0.locationSignature, $0) }, uniquingKeysWith: { a, _ in a })
        all = stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Disk cache

    private struct Cache: Codable {
        var savedAt: Date
        var stations: [TrainStation]
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "stations-v1.json")
    }

    private static func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cache.self, from: data)
    }

    private static func writeCache(_ stations: [TrainStation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Cache(savedAt: .now, stations: stations)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
