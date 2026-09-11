import AppIntents
import Foundation

/// Which saved train a widget shows. Nil means "the next upcoming one".
struct SavedTrainConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Saved train"
    static let description = IntentDescription("Follow one of your saved trains from the Home Screen or Lock Screen.")

    @Parameter(title: "Train", description: "Leave empty to always show the next upcoming saved train.")
    var train: SavedTrainEntity?
}

struct SavedTrainEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved train")
    static let defaultQuery = SavedTrainQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    @MainActor
    init(snapshot: TrainSnapshot, names: StationNames) {
        id = snapshot.id
        title = "\(snapshot.productName ?? String(localized: "Train")) \(snapshot.ident) · \(Format.day(snapshot.departureDate))"
        subtitle = "\(names.name(snapshot.originSignature)) → \(names.name(snapshot.destinationSignature))"
    }
}

struct SavedTrainQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SavedTrainEntity] {
        let all = try await suggestedEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [SavedTrainEntity] {
        let names = StationNames.loadCached()
        return await MainActor.run {
            WidgetEnvironment.savedTrains().filter { !$0.isOver }.map { SavedTrainEntity(snapshot: $0, names: names) }
        }
    }
}
