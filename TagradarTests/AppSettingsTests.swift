import Foundation
@testable import Tagradar
import Testing

@Suite("AppSettings recent trains")
@MainActor
struct AppSettingsTests {
    private let suiteName = "AppSettingsTests-\(UUID().uuidString)"

    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    /// A run departing today, so it survives the "is this still current" filter.
    private func train(_ ident: String, day: Date = .now) -> RecentTrain {
        var recent = RecentTrain(key: TrainKey(ident: ident, departureDate: day), journey: nil)
        recent.scheduledDeparture = day
        recent.scheduledArrival = day.addingTimeInterval(3600)
        return recent
    }

    @Test("Opening a train puts it first")
    func addPutsItFirst() {
        let settings = settings()
        settings.addRecentTrain(train("542"))
        settings.addRecentTrain(train("1234"))
        #expect(settings.recentTrains.map(\.ident) == ["1234", "542"])
    }

    @Test("Reopening a train moves it to the front instead of duplicating it")
    func reopenMovesToFrontWithoutDuplicating() {
        let settings = settings()
        settings.addRecentTrain(train("542"))
        settings.addRecentTrain(train("1234"))
        settings.addRecentTrain(train("542"))
        #expect(settings.recentTrains.map(\.ident) == ["542", "1234"])
    }

    @Test("The same number on another day is a separate run")
    func sameNumberOnAnotherDayIsSeparate() {
        let settings = settings()
        let tomorrow = Date.now.addingTimeInterval(24 * 3600)
        settings.addRecentTrain(train("542"))
        settings.addRecentTrain(train("542", day: tomorrow))
        // Both survive, and by key rather than by number — a count alone would pass even if the
        // wrong one had been kept twice.
        #expect(settings.recentTrains.map(\.id) == [
            TrainKey(ident: "542", departureDate: tomorrow).id,
            TrainKey(ident: "542", departureDate: .now).id,
        ])
    }

    @Test("Only the 8 most recent trains are kept")
    func capsAtEight() {
        let settings = settings()
        for ident in 1 ... 9 {
            settings.addRecentTrain(train(String(ident)))
        }
        #expect(settings.recentTrains.map(\.ident) == ["9", "8", "7", "6", "5", "4", "3", "2"])
    }

    @Test("A run whose journey is over is no longer offered")
    func dropsFinishedRuns() {
        let settings = settings()
        let yesterday = Date.now.addingTimeInterval(-24 * 3600)
        settings.addRecentTrain(train("542", day: yesterday))
        settings.addRecentTrain(train("1234"))
        #expect(settings.recentTrains.map(\.ident) == ["1234"])
    }

    /// Storing it anyway would spend one of the eight slots on a run the card can never show,
    /// evicting one it can — the list would look like it had lost a train for no reason.
    @Test("A run that is already over never takes a slot")
    func finishedRunsNeverTakeASlot() {
        let settings = settings()
        let yesterday = Date.now.addingTimeInterval(-24 * 3600)
        for ident in 1 ... 8 {
            settings.addRecentTrain(train(String(ident)))
        }
        settings.addRecentTrain(train("542", day: yesterday))
        #expect(settings.recentTrains.map(\.ident) == ["8", "7", "6", "5", "4", "3", "2", "1"])
    }

    @Test("The list survives a new instance reading the same defaults")
    func persistsAcrossInstances() {
        let settings = settings()
        settings.addRecentTrain(train("542"))
        let reopened = self.settings()
        #expect(reopened.recentTrains.map(\.ident) == ["542"])
        #expect(reopened.recentTrains.first?.scheduledArrival != nil)
    }
}
