import Foundation
import SwiftData
import TrafikverketKit

/// Composition root. Owns every long-lived service and wires them together.
@MainActor
@Observable
final class AppDependencies {
    let settings: AppSettings
    let apiKeyStore: APIKeyStore
    let client: TrafikverketClient
    let stations: StationDirectory
    let live: LiveTrainStore
    let delays: DelayIndex
    let trains: TrainService
    let journeys: JourneyStore
    let modelContainer: ModelContainer

    private var started = false

    init() {
        let settings = AppSettings()
        let keyStore = APIKeyStore()
        let client = TrafikverketClient(keyProvider: keyStore)
        self.settings = settings
        apiKeyStore = keyStore
        self.client = client
        stations = StationDirectory(client: client)
        live = LiveTrainStore(client: client, settings: settings)
        delays = DelayIndex(client: client)
        let trains = TrainService(client: client)
        self.trains = trains
        journeys = JourneyStore(service: trains)
        do {
            modelContainer = try ModelContainer(for: FavoriteTrain.self)
        } catch {
            // Fall back to an in-memory store rather than crashing on a corrupt database.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            modelContainer = try! ModelContainer(for: FavoriteTrain.self, configurations: config)
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        await stations.load()
        live.start()
    }
}
