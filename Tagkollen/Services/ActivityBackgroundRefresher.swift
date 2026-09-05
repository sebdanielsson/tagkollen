import Foundation
import os
import TrafikverketKit
import UIKit
import WidgetKit

/// Keeps Live Activities (and widgets) moving while the app is in the background, without a push server.
///
/// iOS gives suspended apps no timer, but a background `URLSession` transfer is carried out by the
/// system and, when it finishes, the app is woken for a few seconds to handle the result. The catch is
/// that transfers *created while the app is in the background* are always treated as discretionary,
/// and discretionary transfers wait for Wi-Fi and power, so a chain that schedules the next poll from
/// each wake-up stalls on a train. Instead, the whole polling horizon is scheduled while the app is
/// still in the foreground (`prepareForBackground()`, called when the scene becomes inactive): one
/// small Trafikverket query per expected refresh, each with its own `earliestBeginDate`. Wake-ups
/// then only update the activity, reload widgets and, if the horizon runs short, top it up
/// (those top-ups are discretionary and best effort).
///
/// Cadence: every minute while the train runs, every 3 minutes in the last 45 minutes before
/// departure, sparser before that, and nothing once the train (or the user's part of it) has arrived.
@MainActor
final class ActivityBackgroundRefresher: NSObject {
    static let sessionIdentifier = "se.tagkollen.app.activity-refresh"
    /// Upper bound on pre-scheduled polls per train; at one a minute that is two and a half hours.
    nonisolated static let maxScheduledPolls = 150
    /// Keep polling this long past the expected arrival, in case the train is later than estimated.
    nonisolated static let arrivalGrace: TimeInterval = 25 * 60

    private let trains: TrainService
    private let client: TrafikverketClient
    private let activities: LiveActivityController
    private let segments: () -> [String: TripSegment?]
    private let logger = Logger(subsystem: "se.tagkollen.app", category: "ActivityRefresh")
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
        self.segments = segments
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

    /// The moments to poll at, from `now` until the train should have arrived, following the cadence
    /// above as the trip progresses. Empty when the activity is finished.
    nonisolated static func pollDates(for state: TrainActivityAttributes.ContentState, now: Date = .now) -> [Date] {
        guard state.status == .scheduled || state.status == .enRoute else { return [] }
        let departure = state.expectedDeparture ?? now
        let arrival = (state.expectedArrival ?? departure.addingTimeInterval(3 * 3600)).addingTimeInterval(arrivalGrace)
        var dates: [Date] = []
        var cursor = now
        while dates.count < maxScheduledPolls, cursor < arrival {
            let step: TimeInterval = if state.status == .enRoute || cursor >= departure {
                60
            } else if departure.timeIntervalSince(cursor) < 45 * 60 {
                3 * 60
            } else {
                min(max(departure.timeIntervalSince(cursor) / 4, 10 * 60), 60 * 60)
            }
            cursor = cursor.addingTimeInterval(step)
            dates.append(cursor)
        }
        return dates
    }

    // MARK: Scheduling

    /// Call while the app is still in the foreground (scene phase `.inactive`): replaces pending
    /// polls with a fresh, non-discretionary horizon for every followed train.
    func prepareForBackground() {
        Task { await rescheduleHorizon(reason: "leaving foreground") }
    }

    /// Fallback for the background phase: only schedules if nothing is pending (transfers created
    /// here are discretionary).
    func ensureScheduled() {
        Task {
            if await session.allTasks.isEmpty {
                await rescheduleHorizon(reason: "background fallback")
            }
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

    private func rescheduleHorizon(reason: String) async {
        for task in await session.allTasks {
            task.cancel()
        }
        for (id, state) in activities.currentStates() {
            guard let key = TrainKey(id: id) else { continue }
            let dates = Self.pollDates(for: state)
            await schedule(key: key, at: dates)
            logger.info("Scheduled \(dates.count) polls for \(id, privacy: .public) (\(reason, privacy: .public))")
        }
    }

    private func schedule(key: TrainKey, at dates: [Date]) async {
        guard !dates.isEmpty else { return }
        do {
            var request = try await client.request(for: trains.journeyQuery(for: key))
            guard let body = request.httpBody else { return }
            request.httpBody = nil
            // Background sessions only upload from files; one body file serves every poll.
            let file = FileManager.default.temporaryDirectory.appending(path: "activity-refresh-\(key.id).xml")
            try body.write(to: file, options: .atomic)
            for date in dates {
                let task = session.uploadTask(with: request, fromFile: file)
                task.taskDescription = key.id
                task.earliestBeginDate = date
                task.countOfBytesClientExpectsToSend = Int64(body.count)
                task.countOfBytesClientExpectsToReceive = 60 * 1024
                task.resume()
            }
        } catch {
            logger.error("Could not schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingCount(for trainID: String) async -> Int {
        await session.allTasks.filter { $0.taskDescription == trainID && ($0.state == .suspended || $0.state == .running) }.count
    }

    private func cancelPolls(for trainID: String) async {
        for task in await session.allTasks where task.taskDescription == trainID {
            task.cancel()
        }
    }

    // MARK: Handling results

    /// Stored from `application(_:handleEventsForBackgroundURLSession:completionHandler:)` and called once
    /// every event has been delivered, so the system can suspend the app again.
    func handleEvents(completion: @escaping () -> Void) {
        systemCompletion = completion
    }

    private func handleResponse(trainID: String, data: Data) async {
        guard let key = TrainKey(id: trainID) else { return }
        guard activities.isFollowing(trainID) else {
            await cancelPolls(for: trainID)
            return
        }
        let names = StationNames.loadCached()
        do {
            guard let journey = try TrainService.journey(for: key, responseData: data) else { return }
            let segment: TripSegment? = if let saved = segments()[trainID] {
                saved
            } else {
                nil
            }
            let snapshot = TrainSnapshot(journey: journey, segment: segment)
            await activities.update(snapshot, names: names)
            WidgetCenter.shared.reloadAllTimelines()
            if !activities.isFollowing(trainID) {
                // Arrived or canceled: nothing more to poll for.
                await cancelPolls(for: trainID)
            } else if await pendingCount(for: trainID) < 5, let state = activities.currentStates()[trainID] {
                // Horizon nearly used up (e.g. the train is much later than planned); top it up.
                await schedule(key: key, at: Array(Self.pollDates(for: state).prefix(30)))
            }
        } catch {
            logger.error("Background refresh decode failed: \(error.localizedDescription, privacy: .public)")
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
        let cancelled = (error as? URLError)?.code == .cancelled
        let status = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            let data = received.removeValue(forKey: id) ?? Data()
            guard let trainID, !cancelled else { return }
            if let failure {
                logger.error("Background refresh failed for \(trainID, privacy: .public): \(failure, privacy: .public)")
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
            // Give the completion handlers above a moment to update the activity before the app is suspended again.
            try? await Task.sleep(for: .seconds(2))
            systemCompletion?()
            systemCompletion = nil
        }
    }
}
