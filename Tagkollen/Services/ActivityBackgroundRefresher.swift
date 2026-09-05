import Foundation
import os
import TrafikverketKit
import UIKit

/// Keeps Live Activities moving while the app is in the background without a push server.
///
/// iOS gives suspended apps no timer, but a background `URLSession` transfer is carried out by the
/// system and, when it finishes, the app is woken for a few seconds to handle the result. This class
/// schedules one small Trafikverket query per followed train with an `earliestBeginDate`, updates the
/// activity from the response and schedules the next one, so the activity refreshes roughly once a
/// minute while the train runs and much less often while it is still hours away.
///
/// Limits: the system treats transfers scheduled from the background as discretionary, so on a poor
/// connection it may hold them back and the cadence gets coarser. Each wake costs a little battery,
/// which is why the interval grows when nothing is about to happen and polling stops once the train
/// (or the user's part of it) has arrived.
@MainActor
final class ActivityBackgroundRefresher: NSObject {
    static let sessionIdentifier = "se.sebastiandanielsson.tagkollen.activity-refresh"

    private let trains: TrainService
    private let client: TrafikverketClient
    private let activities: LiveActivityController
    private let modelContainer: () -> [String: TripSegment?]
    private let logger = Logger(subsystem: "se.sebastiandanielsson.tagkollen", category: "ActivityRefresh")
    private var received: [Int: Data] = [:]
    private var systemCompletion: (() -> Void)?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// - Parameter segments: returns the saved trip segment per train id, so background updates respect "your stops".
    init(
        trains: TrainService,
        client: TrafikverketClient,
        activities: LiveActivityController,
        segments: @escaping () -> [String: TripSegment?]
    ) {
        self.trains = trains
        self.client = client
        self.activities = activities
        modelContainer = segments
        super.init()
        _ = session
    }

    // MARK: Cadence

    /// How long to wait before the next background poll for a train in this state.
    nonisolated static func interval(for state: TrainActivityAttributes.ContentState, now: Date = .now) -> TimeInterval? {
        switch state.status {
        case .arrived, .canceled:
            return nil
        case .enRoute:
            return 60
        case .scheduled:
            let departure = state.expectedDeparture ?? .distantFuture
            let untilDeparture = departure.timeIntervalSince(now)
            if untilDeparture < 45 * 60 {
                return 3 * 60
            }
            return min(max(untilDeparture / 4, 10 * 60), 60 * 60)
        }
    }

    /// Schedules one poll per followed train. Called when the app goes to the background and after
    /// each background update. Existing pending polls are replaced.
    func scheduleAll() {
        Task { await scheduleAllPolls() }
    }

    private func scheduleAllPolls() async {
        let pending = await session.allTasks
        for task in pending {
            task.cancel()
        }
        for (id, state) in activities.currentStates() {
            guard let key = TrainKey(id: id), let interval = Self.interval(for: state) else { continue }
            await schedule(key: key, after: interval)
        }
    }

    /// Cancels pending polls; the foreground loop takes over.
    func cancelAll() {
        Task {
            for task in await session.allTasks {
                task.cancel()
            }
        }
    }

    private func schedule(key: TrainKey, after interval: TimeInterval) async {
        do {
            var request = try await client.request(for: trains.journeyQuery(for: key))
            guard let body = request.httpBody else { return }
            request.httpBody = nil
            // Background sessions only upload from files.
            let file = FileManager.default.temporaryDirectory.appending(path: "activity-refresh-\(key.id).xml")
            try body.write(to: file, options: .atomic)
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = key.id
            task.earliestBeginDate = .now.addingTimeInterval(interval)
            task.countOfBytesClientExpectsToSend = Int64(body.count)
            task.countOfBytesClientExpectsToReceive = 60 * 1024
            task.resume()
            logger.info("Scheduled background refresh for \(key.id, privacy: .public) in \(Int(interval))s")
        } catch {
            logger.error("Could not schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Handling results

    /// Stored from `application(_:handleEventsForBackgroundURLSession:completionHandler:)` and called once
    /// every event has been delivered, so the system can suspend the app again.
    func handleEvents(completion: @escaping () -> Void) {
        systemCompletion = completion
    }

    private func handleResponse(trainID: String, data: Data) async {
        guard let key = TrainKey(id: trainID), activities.isFollowing(trainID) else { return }
        let names = StationNames.loadCached()
        do {
            guard let journey = try TrainService.journey(for: key, responseData: data) else { return }
            let segment: TripSegment? = if let saved = modelContainer()[trainID] {
                saved
            } else {
                nil
            }
            let snapshot = TrainSnapshot(journey: journey, segment: segment)
            await activities.update(snapshot, names: names)
            if activities.isFollowing(trainID), let state = activities.currentStates()[trainID],
               let interval = Self.interval(for: state) {
                await schedule(key: key, after: interval)
            }
        } catch {
            logger.error("Background refresh decode failed: \(error.localizedDescription, privacy: .public)")
            // Try again later rather than giving up on a transient API error.
            await schedule(key: key, after: 3 * 60)
        }
    }
}

extension ActivityBackgroundRefresher: URLSessionDataDelegate {
    nonisolated func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        Task { @MainActor in
            received[id, default: Data()].append(data)
        }
    }

    nonisolated func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let id = task.taskIdentifier
        let trainID = task.taskDescription
        let failure = error?.localizedDescription
        let status = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            let data = received.removeValue(forKey: id) ?? Data()
            guard let trainID else { return }
            if let failure {
                if (error as? URLError)?.code != .cancelled {
                    logger.error("Background refresh failed for \(trainID, privacy: .public): \(failure, privacy: .public)")
                    if let key = TrainKey(id: trainID), activities.isFollowing(trainID) {
                        await schedule(key: key, after: 3 * 60)
                    }
                }
                return
            }
            guard status.map({ (200 ... 299).contains($0) }) ?? true else {
                logger.error("Background refresh HTTP \(status ?? 0) for \(trainID, privacy: .public)")
                return
            }
            await handleResponse(trainID: trainID, data: data)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        Task { @MainActor in
            // Give the completion handlers above a moment to update the activity and schedule the next poll.
            try? await Task.sleep(for: .seconds(2))
            systemCompletion?()
            systemCompletion = nil
        }
    }
}
