import ActivityKit
import Foundation
import os

/// Starts, updates and ends the Live Activity for followed trains.
@MainActor
@Observable
final class LiveActivityController {
    typealias Content = ActivityContent<TrainActivityAttributes.ContentState>

    private(set) var followedIDs: Set<String> = []
    private let logger = Logger(subsystem: "se.sebastiandanielsson.tagkollen", category: "LiveActivity")
    /// How long a state stays fresh before the system dims it. Matches the background refresh cadence.
    private static let staleAfter: TimeInterval = 20 * 60

    init() {
        restore()
    }

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Picks up activities that survived an app relaunch.
    func restore() {
        followedIDs = Set(Activity<TrainActivityAttributes>.activities.map(\.attributes.trainID))
    }

    func isFollowing(_ id: String) -> Bool {
        followedIDs.contains(id)
    }

    func follow(_ snapshot: TrainSnapshot, names: StationNames) throws {
        let content = Self.content(for: snapshot, names: names)
        if followedIDs.contains(snapshot.id) {
            Task { await Self.update(id: snapshot.id, content: content) }
            return
        }
        let attributes = TrainActivityAttributes(snapshot: snapshot, names: names)
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        followedIDs.insert(snapshot.id)
        logger.info("Following train \(snapshot.id, privacy: .public)")
    }

    /// Pushes a refreshed state; ends the activity a while after the train (or the user) has arrived.
    func update(_ snapshot: TrainSnapshot, names: StationNames) async {
        let content = Self.content(for: snapshot, names: names)
        switch content.state.status {
        case .arrived, .canceled:
            await Self.end(id: snapshot.id, content: content, dismissal: .after(.now.addingTimeInterval(15 * 60)))
            followedIDs.remove(snapshot.id)
        case .scheduled, .enRoute:
            let stillRunning = await Self.update(id: snapshot.id, content: content)
            if !stillRunning {
                followedIDs.remove(snapshot.id)
            }
        }
    }

    func unfollow(_ id: String) async {
        await Self.end(id: id, content: nil, dismissal: .immediate)
        followedIDs.remove(id)
    }

    func unfollowAll() async {
        for id in followedIDs {
            await Self.end(id: id, content: nil, dismissal: .immediate)
        }
        followedIDs = []
    }

    private static func content(for snapshot: TrainSnapshot, names: StationNames) -> Content {
        ActivityContent(
            state: TrainActivityAttributes.ContentState(snapshot: snapshot, names: names),
            staleDate: .now.addingTimeInterval(staleAfter)
        )
    }

    // `Activity` is not Sendable, so it is looked up and used within one nonisolated context.

    @discardableResult
    private nonisolated static func update(id: String, content: Content) async -> Bool {
        guard let activity = Activity<TrainActivityAttributes>.activities.first(where: { $0.attributes.trainID == id }) else {
            return false
        }
        await activity.update(content)
        return true
    }

    private nonisolated static func end(id: String, content: Content?, dismissal: ActivityUIDismissalPolicy) async {
        guard let activity = Activity<TrainActivityAttributes>.activities.first(where: { $0.attributes.trainID == id }) else { return }
        await activity.end(content, dismissalPolicy: dismissal)
    }
}
