import Foundation
import SwiftData

/// A pinned train run. Stored with enough context to render a row without a network call.
@Model
final class FavoriteTrain {
    @Attribute(.unique) var id: String
    var ident: String
    var departureDate: Date
    var originSignature: String?
    var destinationSignature: String?
    var productName: String?
    var operatorName: String?
    var scheduledDeparture: Date?
    var scheduledArrival: Date?
    var note: String
    var createdAt: Date

    init(key: TrainKey, journey: TrainJourney?, note: String = "") {
        id = key.id
        ident = key.ident
        departureDate = key.departureDate
        originSignature = journey?.origin?.signature
        destinationSignature = journey?.destination?.signature
        productName = journey?.productName
        operatorName = journey?.operatorName
        scheduledDeparture = journey?.scheduledDeparture
        scheduledArrival = journey?.scheduledArrival
        self.note = note
        createdAt = .now
    }

    var key: TrainKey {
        TrainKey(ident: ident, departureDate: departureDate)
    }

    /// Refreshes the cached summary fields from a freshly loaded journey.
    func update(from journey: TrainJourney) {
        originSignature = journey.origin?.signature ?? originSignature
        destinationSignature = journey.destination?.signature ?? destinationSignature
        productName = journey.productName ?? productName
        operatorName = journey.operatorName ?? operatorName
        scheduledDeparture = journey.scheduledDeparture ?? scheduledDeparture
        scheduledArrival = journey.scheduledArrival ?? scheduledArrival
    }
}
