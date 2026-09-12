@testable import Tagradar
import Foundation
import Testing

@Suite("AppSettings recent train searches")
@MainActor
struct AppSettingsTests {
    private func settings() -> AppSettings {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    @Test("Adding a search puts it first")
    func addPutsItFirst() {
        let settings = settings()
        settings.addRecentTrainSearch("542")
        settings.addRecentTrainSearch("1234")
        #expect(settings.recentTrainSearches == ["1234", "542"])
    }

    @Test("Re-adding an existing search moves it to the front instead of duplicating it")
    func readdMovesToFrontWithoutDuplicating() {
        let settings = settings()
        settings.addRecentTrainSearch("542")
        settings.addRecentTrainSearch("1234")
        settings.addRecentTrainSearch("542")
        #expect(settings.recentTrainSearches == ["542", "1234"])
    }

    @Test("Only the 8 most recent searches are kept")
    func capsAtEight() {
        let settings = settings()
        for ident in 1 ... 9 {
            settings.addRecentTrainSearch(String(ident))
        }
        #expect(settings.recentTrainSearches.count == 8)
        #expect(settings.recentTrainSearches == ["9", "8", "7", "6", "5", "4", "3", "2"])
    }
}
