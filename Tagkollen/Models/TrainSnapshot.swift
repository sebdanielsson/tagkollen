import Foundation

/// A saved train reduced to plain values: what the widgets and notifications need to render a
/// row without touching SwiftData or the network. Filled from the favorite first, then from a
/// freshly loaded journey when one is available.
struct TrainSnapshot: Hashable, Sendable, Identifiable {
    let id: String
    let ident: String
    let departureDate: Date
    var productName: String?
    var originSignature: String?
    var destinationSignature: String?
    var scheduledDeparture: Date?
    var scheduledArrival: Date?
    /// The user's part of the run; nil means the whole run. All live fields below are relative to it.
    var segment: TripSegment?

    var status: TrainJourney.Status?
    var delay: TimeInterval?
    var expectedDeparture: Date?
    var expectedArrival: Date?
    var originTrack: String?
    var nextStopSignature: String?
    var nextStopPlanned: Date?
    var nextStopExpected: Date?
    var nextStopTrack: String?
    var lastPassedSignature: String?
    var lastPassedTime: Date?
    var progress: Double = 0
    var updatedAt: Date?
    /// Stops after the next one, within the segment.
    var upcomingStops: [UpcomingStop] = []

    struct UpcomingStop: Hashable, Sendable {
        var signature: String
        var expected: Date?
        var track: String?
    }

    init(favorite: FavoriteTrain) {
        id = favorite.id
        ident = favorite.ident
        departureDate = favorite.departureDate
        productName = favorite.productName
        originSignature = favorite.originSignature
        destinationSignature = favorite.destinationSignature
        scheduledDeparture = favorite.scheduledDeparture
        scheduledArrival = favorite.scheduledArrival
        segment = favorite.segment
        if let segment, let boarding = segment.boarding {
            originSignature = boarding
            scheduledDeparture = favorite.boardingTime
        }
        if let segment, let alighting = segment.alighting {
            destinationSignature = alighting
            scheduledArrival = favorite.alightingTime
        }
    }

    init(journey: TrainJourney, segment: TripSegment? = nil) {
        id = journey.key.id
        ident = journey.key.ident
        departureDate = journey.key.departureDate
        self.segment = segment
        apply(journey)
    }

    var key: TrainKey {
        TrainKey(ident: ident, departureDate: departureDate)
    }

    var deepLink: URL {
        URL(string: "tagkollen://train/\(id)")!
    }

    var isCanceled: Bool {
        status == .canceled
    }

    /// Departure time to show: the estimate when one exists, otherwise the timetable.
    var bestDeparture: Date? {
        expectedDeparture ?? scheduledDeparture
    }

    var bestArrival: Date? {
        expectedArrival ?? scheduledArrival
    }

    /// True once the train has finished (or should have) so lists can drop it.
    var isOver: Bool {
        if status == .arrived {
            return true
        }
        let end = bestArrival ?? departureDate.addingTimeInterval(36 * 3600)
        return end.addingTimeInterval(30 * 60) < .now
    }

    /// Fills the live fields from a journey. With a segment, "origin" and "destination" become the
    /// boarding and alighting stops and delays, next stop and status are judged for that part only:
    /// a late departure from the run's first station does not matter to someone boarding later.
    mutating func apply(_ journey: TrainJourney) {
        productName = journey.productName ?? productName
        let stops = journey.stops
        guard let range = (segment ?? TripSegment(boarding: nil, alighting: nil))?.range(in: stops) ?? Self.wholeRange(stops) else {
            status = journey.status
            updatedAt = journey.latestModified ?? .now
            return
        }
        let part = Array(stops[range])
        let first = part.first
        let last = part.last
        originSignature = first?.signature ?? originSignature
        destinationSignature = last?.signature ?? destinationSignature
        // The boarding stop's departure, or its arrival at a drop-off-only stop; the alighting stop's arrival.
        let departureRow = first?.departure ?? first?.arrival
        let arrivalRow = last?.arrival ?? last?.departure
        scheduledDeparture = departureRow?.advertisedTimeAtLocation ?? scheduledDeparture
        scheduledArrival = arrivalRow?.advertisedTimeAtLocation ?? scheduledArrival
        expectedDeparture = departureRow?.bestKnownTime
        expectedArrival = arrivalRow?.bestKnownTime
        originTrack = first?.track

        let boarded = first?.hasPassed ?? false
        let done = last?.hasArrived ?? false
        if part.allSatisfy(\.isCanceled) || (first?.isCanceled ?? false) || (last?.isCanceled ?? false) {
            status = .canceled
        } else if done {
            status = .arrived
        } else if boarded {
            status = .enRoute
        } else {
            status = .scheduled
        }

        let remaining = part.filter { !$0.hasPassed && !$0.isCanceled }
        let next = remaining.first
        upcomingStops = remaining.dropFirst().prefix(4).map {
            UpcomingStop(signature: $0.signature, expected: $0.arrival?.bestKnownTime ?? $0.departure?.bestKnownTime, track: $0.track)
        }
        nextStopSignature = boarded ? next?.signature : nil
        nextStopPlanned = next?.arrival?.advertisedTimeAtLocation ?? next?.departure?.advertisedTimeAtLocation
        nextStopExpected = next?.arrival?.bestKnownTime ?? next?.departure?.bestKnownTime
        nextStopTrack = next?.track
        delay = switch status {
        case .scheduled: departureRow?.delay
        case .enRoute: next?.arrival?.delay ?? next?.departure?.delay ?? part.last(where: \.hasPassed)?.delay
        case .arrived: arrivalRow?.delay
        case .canceled, nil: nil
        }
        // Reports from before the boarding stop are still useful context ("passed X 12:55").
        lastPassedSignature = journey.lastReport?.signature
        lastPassedTime = journey.lastReport?.time
        let total = part.count
        let passed = part.filter(\.hasPassed).count
        progress = total > 1 ? min(1, Double(passed) / Double(total - 1)) : (done ? 1 : 0)
        updatedAt = journey.latestModified ?? .now
    }

    private static func wholeRange(_ stops: [TrainStop]) -> ClosedRange<Int>? {
        stops.isEmpty ? nil : 0 ... (stops.count - 1)
    }
}
