import AppIntents
import Foundation

/// Which station's departure board a widget shows. Nil means the first favorite station.
struct StationDeparturesConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Departures"
    static let description = IntentDescription("The next departures from a station.")

    @Parameter(title: "Station", description: "Leave empty to use your first favorite station.")
    var station: StationEntity?
}

struct StationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Station")
    static let defaultQuery = StationQuery()

    /// The Trafikverket location signature, e.g. `Cst`.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct StationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        let names = await names()
        return identifiers.compactMap { id in names.station(id).map { StationEntity(id: id, name: $0.name) } }
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        let names = await names()
        let folded = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return names.all
            .filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(folded) }
            .prefix(30)
            .map { StationEntity(id: $0.locationSignature, name: $0.name) }
    }

    func suggestedEntities() async throws -> [StationEntity] {
        let favorites = await MainActor.run { WidgetEnvironment.favoriteStations() }
        if !favorites.isEmpty {
            return favorites.map { StationEntity(id: $0.signature, name: $0.name) }
        }
        let names = await names()
        return ["Cst", "G", "M", "U", "Lp", "Nr", "Vå", "Öb"].compactMap { sig in
            names.station(sig).map { StationEntity(id: sig, name: $0.name) }
        }
    }

    private func names() async -> StationNames {
        let client = await MainActor.run { WidgetEnvironment.makeClient() }
        return await WidgetEnvironment.stationNames(client: client)
    }
}
