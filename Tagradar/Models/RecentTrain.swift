import Foundation

/// A train run the user has opened, kept so they can find their way back to it without
/// remembering the number. Stored with enough context to render a row without a network call,
/// like `FavoriteTrain` — the difference is that nobody chose to keep this one.
struct RecentTrain: Codable, Hashable, Identifiable, Sendable {
    var ident: String
    var departureDate: Date
    var originSignature: String?
    var destinationSignature: String?
    var productName: String?
    var scheduledDeparture: Date?
    var scheduledArrival: Date?
    /// When the user last opened it, which is what the list sorts by.
    var openedAt: Date

    var id: String {
        key.id
    }

    var key: TrainKey {
        TrainKey(ident: ident, departureDate: departureDate)
    }

    init(key: TrainKey, journey: TrainJourney?, openedAt: Date = .now) {
        ident = key.ident
        departureDate = key.departureDate
        originSignature = journey?.origin?.signature
        destinationSignature = journey?.destination?.signature
        productName = journey?.productName
        scheduledDeparture = journey?.scheduledDeparture
        scheduledArrival = journey?.scheduledArrival
        self.openedAt = openedAt
    }

    /// Fills the gaps of a favorite saved before its journey was loaded, so the row it turns into
    /// reads the same as the one the user just tapped the star on. Returns whether anything
    /// changed, so a caller sweeping the list can tell an actual repair from a no-op and save only
    /// for the former.
    @discardableResult
    func fillIn(_ favorite: FavoriteTrain) -> Bool {
        var changed = false
        func fill<Value>(_ keyPath: ReferenceWritableKeyPath<FavoriteTrain, Value?>, _ value: Value?) {
            guard favorite[keyPath: keyPath] == nil, let value else { return }
            favorite[keyPath: keyPath] = value
            changed = true
        }
        fill(\.originSignature, originSignature)
        fill(\.destinationSignature, destinationSignature)
        fill(\.productName, productName)
        fill(\.scheduledDeparture, scheduledDeparture)
        fill(\.scheduledArrival, scheduledArrival)
        return changed
    }

    /// Whether the run is still worth offering. A journey that ended hours ago is history, not a
    /// shortcut — the same window the saved tab uses, so the two never retire a run at
    /// different times.
    func isCurrent(now: Date = .now) -> Bool {
        TrainSnapshot.isCurrentRun(departureDate: departureDate, scheduledArrival: scheduledArrival, now: now)
    }
}
