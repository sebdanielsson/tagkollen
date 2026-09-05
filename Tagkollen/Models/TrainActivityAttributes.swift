import ActivityKit
import Foundation

/// Live Activity payload for one followed train. The attributes are fixed for the run; the
/// content state is replaced on every refresh.
struct TrainActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable {
            case scheduled, enRoute, arrived, canceled
        }

        var status: Status
        var delaySeconds: Int?
        var nextStopName: String?
        var nextStopPlanned: Date?
        var nextStopExpected: Date?
        var nextStopTrack: String?
        var lastPassedName: String?
        var lastPassedTime: Date?
        var expectedDeparture: Date?
        var expectedArrival: Date?
        var originTrack: String?
        /// 0…1 share of the stops already passed.
        var progress: Double
        var updatedAt: Date
        /// The stops after the next one, so the activity can show what is coming without another update.
        var upcoming: [UpcomingStop] = []

        struct UpcomingStop: Codable, Hashable, Sendable {
            var name: String
            var expected: Date?
            var track: String?
        }

        /// Interval the UI can animate through between refreshes: from the last report to the next
        /// expected stop. Nil when the train is not en route or either end is unknown.
        var legInterval: ClosedRange<Date>? {
            guard status == .enRoute, let from = lastPassedTime, let to = nextStopExpected ?? nextStopPlanned, from < to else {
                return nil
            }
            return from ... to
        }

        var delay: TimeInterval? {
            delaySeconds.map(TimeInterval.init)
        }

        init(snapshot: TrainSnapshot, names: StationNames) {
            status = switch snapshot.status {
            case .canceled: .canceled
            case .arrived: .arrived
            case .enRoute: .enRoute
            case .scheduled, nil: .scheduled
            }
            delaySeconds = snapshot.delay.map { Int($0) }
            nextStopName = snapshot.nextStopSignature.map(names.shortName)
            nextStopPlanned = snapshot.nextStopPlanned
            nextStopExpected = snapshot.nextStopExpected
            nextStopTrack = snapshot.nextStopTrack
            lastPassedName = snapshot.lastPassedSignature.map(names.shortName)
            lastPassedTime = snapshot.lastPassedTime
            expectedDeparture = snapshot.expectedDeparture
            expectedArrival = snapshot.expectedArrival
            originTrack = snapshot.originTrack
            progress = snapshot.progress
            updatedAt = snapshot.updatedAt ?? .now
            upcoming = snapshot.upcomingStops.prefix(3).map {
                UpcomingStop(name: names.shortName($0.signature), expected: $0.expected, track: $0.track)
            }
        }
    }

    let trainID: String
    let ident: String
    let productName: String?
    let originName: String
    let destinationName: String
    let scheduledDeparture: Date?
    let scheduledArrival: Date?

    init(snapshot: TrainSnapshot, names: StationNames) {
        trainID = snapshot.id
        ident = snapshot.ident
        productName = snapshot.productName
        originName = names.name(snapshot.originSignature)
        destinationName = names.name(snapshot.destinationSignature)
        scheduledDeparture = snapshot.scheduledDeparture
        scheduledArrival = snapshot.scheduledArrival
    }

    var deepLink: URL {
        URL(string: "tagkollen://train/\(trainID)")!
    }

    var title: String {
        "\(productName ?? String(localized: "Train")) \(ident)"
    }
}
