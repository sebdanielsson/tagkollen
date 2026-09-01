import Foundation
import TrafikverketKit

/// A full train run assembled from its TrainAnnouncement rows.
struct TrainJourney: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case scheduled
        case enRoute
        case arrived
        case canceled
    }

    let key: TrainKey
    let stops: [TrainStop]
    let announcements: [TrainAnnouncement]

    var id: String {
        key.id
    }

    init(key: TrainKey, announcements: [TrainAnnouncement]) {
        self.key = key
        self.announcements = announcements
        stops = Self.buildStops(from: announcements)
    }

    // MARK: Derived summary

    private var representative: TrainAnnouncement? {
        announcements.first { $0.activityType == .departure } ?? announcements.first
    }

    var productName: String? {
        representative?.productInformation?.compactMap(\.description).first
    }

    var operatorName: String? {
        representative?.operator ?? representative?.trainOwner
    }

    var informationOwner: String? {
        representative?.informationOwner
    }

    var typeOfTraffic: String? {
        representative?.typeOfTraffic?.compactMap(\.description).first
    }

    var webLink: URL? {
        (representative?.webLink ?? representative?.mobileWebLink).flatMap(URL.init(string:))
    }

    var webLinkName: String? {
        representative?.webLinkName
    }

    var operationalTrainNumber: String? {
        representative?.operationalTrainNumber
    }

    var services: [CodeDescription] {
        var seen = Set<String>()
        return announcements.flatMap { $0.service ?? [] }.filter { seen.insert($0.description ?? $0.code ?? "").inserted }
    }

    var origin: TrainStop? {
        stops.first
    }

    var destination: TrainStop? {
        stops.last
    }

    /// Destination signatures as advertised at the origin (what the departure board shows).
    var advertisedDestinationSignatures: [String] {
        (origin?.departure?.toLocation ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map(\.locationName)
    }

    var advertisedOriginSignatures: [String] {
        (destination?.arrival?.fromLocation ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map(\.locationName)
    }

    var status: Status {
        if !stops.isEmpty, stops.allSatisfy(\.isCanceled) {
            return .canceled
        }
        if destination?.hasArrived == true {
            return .arrived
        }
        if stops.contains(where: \.hasPassed) {
            return .enRoute
        }
        return .scheduled
    }

    var isFullyCanceled: Bool {
        status == .canceled
    }

    var hasPartialCancellation: Bool {
        !isFullyCanceled && stops.contains { $0.isCanceled || $0.isPartlyCanceled }
    }

    /// Last stop the train has been reported at.
    var lastPassedStop: TrainStop? {
        stops.last(where: \.hasPassed)
    }

    /// Next stop the train has not yet departed from (or arrived at, for the terminus).
    var nextStop: TrainStop? {
        stops.first { !$0.hasPassed && !$0.isCanceled }
    }

    /// Current delay: taken from the next stop's estimate, else the last reported stop.
    var currentDelay: TimeInterval? {
        if let next = nextStop, let d = next.arrival?.delay ?? next.departure?.delay {
            return d
        }
        return lastPassedStop?.delay
    }

    var scheduledDeparture: Date? {
        origin?.departure?.advertisedTimeAtLocation
    }

    var scheduledArrival: Date? {
        destination?.arrival?.advertisedTimeAtLocation
    }

    var expectedArrival: Date? {
        destination?.arrival?.bestKnownTime
    }

    var latestModified: Date? {
        announcements.compactMap(\.modifiedTime).max()
    }

    var allSignatures: Set<String> {
        Set(stops.map(\.signature))
    }

    // MARK: Building

    static func buildStops(from announcements: [TrainAnnouncement]) -> [TrainStop] {
        var byStation: [String: TrainStop] = [:]
        var order: [String] = []
        for a in announcements {
            guard let sig = a.locationSignature else { continue }
            if byStation[sig] == nil {
                byStation[sig] = TrainStop(signature: sig)
                order.append(sig)
            }
            switch a.activityType {
            case .arrival: byStation[sig]?.arrival = a
            case .departure: byStation[sig]?.departure = a
            case nil: break
            }
        }
        return order.compactMap { byStation[$0] }.sorted { lhs, rhs in
            switch (lhs.sortTime, rhs.sortTime) {
            case let (l?, r?): l < r
            case (nil, _?): false
            case (_?, nil): true
            default: false
            }
        }
    }
}
