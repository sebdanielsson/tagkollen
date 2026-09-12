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
    /// reads the same as the one the user just tapped the star on.
    func fillIn(_ favorite: FavoriteTrain) {
        favorite.originSignature = favorite.originSignature ?? originSignature
        favorite.destinationSignature = favorite.destinationSignature ?? destinationSignature
        favorite.productName = favorite.productName ?? productName
        favorite.scheduledDeparture = favorite.scheduledDeparture ?? scheduledDeparture
        favorite.scheduledArrival = favorite.scheduledArrival ?? scheduledArrival
    }

    /// Whether the run is still worth offering. A journey that ended hours ago is history, not a
    /// shortcut — the same window the saved tab uses, so the two never retire a run at
    /// different times.
    func isCurrent(now: Date = .now) -> Bool {
        TrainSnapshot.isCurrentRun(departureDate: departureDate, scheduledArrival: scheduledArrival, now: now)
    }
}
