import Foundation

/// Bucketed delay used for colouring badges and markers.
enum DelaySeverity: Hashable, Sendable {
    case unknown, onTime, minor, major, canceled

    static func of(delay: TimeInterval?, canceled: Bool) -> DelaySeverity {
        if canceled {
            return .canceled
        }
        guard let delay else { return .unknown }
        let minutes = delay / 60
        if minutes < 3 {
            return .onTime
        }
        if minutes < 15 {
            return .minor
        }
        return .major
    }
}
