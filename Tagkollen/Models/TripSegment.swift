import Foundation

/// The part of a train run a user travels: where they board and where they get off.
/// Either end may be nil, meaning the train's own origin or destination.
struct TripSegment: Hashable, Codable, Sendable {
    var boarding: String?
    var alighting: String?

    /// Nil when neither end is set, so callers can treat "whole run" uniformly.
    init?(boarding: String?, alighting: String?) {
        guard boarding != nil || alighting != nil else { return nil }
        self.boarding = boarding
        self.alighting = alighting
    }

    /// Indices into `stops` for the boarding and alighting stations. Unknown or out-of-order
    /// signatures fall back to the run's ends.
    func range(in stops: [TrainStop]) -> ClosedRange<Int>? {
        guard !stops.isEmpty else { return nil }
        let first = boarding.flatMap { sig in stops.firstIndex { $0.signature == sig } } ?? 0
        let last = alighting.flatMap { sig in stops.lastIndex { $0.signature == sig } } ?? stops.count - 1
        guard first <= last else { return 0 ... (stops.count - 1) }
        return first ... last
    }
}
