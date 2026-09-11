import Foundation

/// What was last told to the user about a saved train, kept between refreshes so only changes
/// produce notifications.
struct TrainAlertState: Codable, Hashable, Sendable {
    /// The delay (whole minutes) the user was last notified about, or first saw.
    var delayMinutes: Int?
    var canceled: Bool
    var track: String?
    var arrived: Bool
    var boarded: Bool
}

enum TrainAlertKind: Hashable, Sendable {
    case delay(minutes: Int, previous: Int?)
    case backOnTime
    case canceled
    case trackChanged(from: String, to: String)
    case arrived(delayMinutes: Int?)
}

/// Pure rules deciding which notifications a refreshed snapshot warrants. The snapshot is already
/// relative to the user's trip segment, so a delay that only affects stations outside it never gets here.
enum TrainAlertEngine {
    /// Delay changes smaller than this (in minutes) are not worth a notification.
    static let delayThresholdMinutes = 5

    static func evaluate(previous: TrainAlertState?, current: TrainSnapshot) -> (alerts: [TrainAlertKind], state: TrainAlertState) {
        let minutes = current.delay.map { Int(($0 / 60).rounded()) }
        let arrived = current.status == .arrived
        var state = TrainAlertState(
            delayMinutes: minutes,
            canceled: current.isCanceled,
            track: current.originTrack,
            arrived: arrived,
            boarded: current.status == .enRoute || arrived
        )
        guard let previous else { return ([], state) }
        // Nothing after the user's alighting station.
        if previous.arrived {
            return ([], previous)
        }
        var alerts: [TrainAlertKind] = []
        if state.canceled, !previous.canceled {
            alerts.append(.canceled)
        }
        if arrived {
            alerts.append(.arrived(delayMinutes: minutes))
        }
        if !state.canceled, !arrived {
            if let minutes {
                let reference = previous.delayMinutes ?? 0
                if abs(minutes - reference) >= delayThresholdMinutes {
                    if minutes >= delayThresholdMinutes {
                        alerts.append(.delay(minutes: minutes, previous: previous.delayMinutes))
                    } else if reference >= delayThresholdMinutes {
                        alerts.append(.backOnTime)
                    }
                } else {
                    state.delayMinutes = previous.delayMinutes
                }
            } else {
                state.delayMinutes = previous.delayMinutes
            }
            if !previous.boarded, let from = previous.track, let to = state.track, from != to {
                alerts.append(.trackChanged(from: from, to: to))
            }
        }
        if previous.canceled, !state.canceled {
            // Un-cancellations are rare enough to just tell the user the current delay next time.
            state.delayMinutes = nil
        }
        return (alerts, state)
    }
}
