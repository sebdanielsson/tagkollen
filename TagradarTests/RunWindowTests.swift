import Foundation
@testable import Tagradar
import Testing

/// `TrainSnapshot.isCurrentRun` decides when a run leaves the map card, for both the saved and the
/// recent tab. The edges are what matter: a grace period nobody exercises is a grace period that
/// can quietly become zero.
@Suite("Run window")
struct RunWindowTests {
    private static let now = Date(timeIntervalSince1970: 1_757_000_000)

    private func isCurrent(arrivingIn seconds: TimeInterval) -> Bool {
        TrainSnapshot.isCurrentRun(
            departureDate: Self.now,
            scheduledArrival: Self.now.addingTimeInterval(seconds),
            now: Self.now
        )
    }

    @Test("A run that arrived just inside the three-hour grace is still on offer")
    func insideTheGrace() {
        #expect(isCurrent(arrivingIn: -3 * 3600 + 60))
    }

    @Test("A run that arrived just outside the three-hour grace is gone")
    func outsideTheGrace() {
        #expect(!isCurrent(arrivingIn: -3 * 3600 - 60))
    }

    /// Without an arrival there is nothing to count from, so the run is assumed to be a long one
    /// rather than dropped on the spot.
    @Test("An unknown arrival keeps the run for 36 hours plus the grace")
    func unknownArrivalFallsBackTo36Hours() {
        func isCurrent(departedAgo seconds: TimeInterval) -> Bool {
            TrainSnapshot.isCurrentRun(
                departureDate: Self.now.addingTimeInterval(-seconds),
                scheduledArrival: nil,
                now: Self.now
            )
        }
        #expect(isCurrent(departedAgo: 38 * 3600))
        #expect(!isCurrent(departedAgo: 40 * 3600))
    }

    /// The two tabs filtered on separately written copies of this rule before; the point of the
    /// shared helper is that they can no longer disagree.
    @Test("A recent train uses the same window")
    func recentTrainMatchesTheHelper() {
        let key = TrainKey(ident: "542", departureDate: Self.now)
        var recent = RecentTrain(key: key, journey: nil)
        recent.scheduledArrival = Self.now.addingTimeInterval(-3 * 3600 - 60)
        #expect(!recent.isCurrent(now: Self.now))
        recent.scheduledArrival = Self.now.addingTimeInterval(-3 * 3600 + 60)
        #expect(recent.isCurrent(now: Self.now))
    }
}
