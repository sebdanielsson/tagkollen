import Foundation
import TrafikverketKit

/// In-memory cache of loaded journeys so the map, detail view and favorites share one copy
/// and the map can draw a route as soon as the detail has loaded it.
@MainActor
@Observable
final class JourneyStore {
    private struct Entry {
        var journey: TrainJourney?
        var loadedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<TrainJourney?, Error>] = [:]
    private let service: TrainService
    private static let maxAge: TimeInterval = 20

    init(service: TrainService) {
        self.service = service
    }

    /// The last loaded journey for a key, if any, regardless of age.
    func cached(_ key: TrainKey?) -> TrainJourney? {
        guard let key else { return nil }
        return entries[key.id]?.journey
    }

    /// Loads the journey, reusing a fresh cached copy or an in-flight request.
    func load(_ key: TrainKey, force: Bool = false) async throws -> TrainJourney? {
        if !force, let entry = entries[key.id], Date.now.timeIntervalSince(entry.loadedAt) < Self.maxAge {
            return entry.journey
        }
        if let task = inFlight[key.id] {
            return try await task.value
        }
        let service = service
        let task = Task<TrainJourney?, Error> { try await service.journey(for: key) }
        inFlight[key.id] = task
        defer { inFlight[key.id] = nil }
        let journey = try await task.value
        entries[key.id] = Entry(journey: journey, loadedAt: .now)
        return journey
    }

    func store(_ journey: TrainJourney) {
        entries[journey.key.id] = Entry(journey: journey, loadedAt: .now)
    }
}
