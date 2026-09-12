import Foundation
import SwiftUI

/// User preferences persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    enum MapAppearance: String, CaseIterable, Identifiable {
        case standard, hybrid, muted
        var id: String {
            rawValue
        }
    }

    var mapAppearance: MapAppearance {
        didSet { defaults.set(mapAppearance.rawValue, forKey: Keys.mapAppearance) }
    }

    var showInactiveTrains: Bool {
        didSet { defaults.set(showInactiveTrains, forKey: Keys.showInactiveTrains) }
    }

    var showTrainLabels: Bool {
        didSet { defaults.set(showTrainLabels, forKey: Keys.showTrainLabels) }
    }

    var colorMarkersByDelay: Bool {
        didSet { defaults.set(colorMarkersByDelay, forKey: Keys.colorMarkersByDelay) }
    }

    /// Ambient, tappable station markers once zoomed in enough (see `StationPins`).
    var showStations: Bool {
        didSet { defaults.set(showStations, forKey: Keys.showStations) }
    }

    var pollingInterval: TimeInterval {
        didSet { defaults.set(pollingInterval, forKey: Keys.pollingInterval) }
    }

    /// Local notifications about saved trains (delays, cancellations, track changes, reminders).
    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    /// Station signatures the user opened most recently, newest first.
    private(set) var recentStations: [String] {
        didSet { defaults.set(recentStations, forKey: Keys.recentStations) }
    }

    func addRecentStation(_ signature: String) {
        var list = recentStations.filter { $0 != signature }
        list.insert(signature, at: 0)
        recentStations = Array(list.prefix(8))
    }

    /// Train runs the user has opened, newest first — not necessarily saved as favorites.
    /// Runs whose journey is over are dropped as they are read, so the stored list never needs
    /// sweeping and a card built from it can't offer a shortcut back to yesterday.
    /// Ordered by `openedAt` rather than by how the list happens to be stored, so the field the
    /// record carries is the one the order actually comes from. The key breaks ties, because
    /// `sorted` is not stable and two runs opened in the same instant would otherwise swap around
    /// between reads.
    var recentTrains: [RecentTrain] {
        storedRecentTrains
            .filter { $0.isCurrent() }
            .sorted { ($0.openedAt, $0.id) > ($1.openedAt, $1.id) }
    }

    /// A run too old to be read back is not stored at all: it would take one of the eight slots
    /// and push out a run the card can still show, so the list would appear to lose a train.
    func addRecentTrain(_ train: RecentTrain) {
        guard train.isCurrent() else { return }
        var list = storedRecentTrains.filter { $0.id != train.id && $0.isCurrent() }
        list.insert(train, at: 0)
        storedRecentTrains = Array(list.prefix(8))
    }

    private var storedRecentTrains: [RecentTrain] {
        didSet {
            // Passing a nil `Data` here would *remove* the key and wipe the history; keeping the
            // last good value is the better failure.
            guard let data = try? JSONEncoder().encode(storedRecentTrains) else { return }
            defaults.set(data, forKey: Keys.recentTrains)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let mapAppearance = "settings.mapAppearance"
        static let showInactiveTrains = "settings.showInactiveTrains"
        static let showTrainLabels = "settings.showTrainLabels"
        static let colorMarkersByDelay = "settings.colorMarkersByDelay"
        static let showStations = "settings.showStations"
        static let pollingInterval = "settings.pollingInterval"
        static let alertsEnabled = "settings.alertsEnabled"
        static let recentStations = "settings.recentStations"
        static let recentTrains = "settings.recentTrains"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mapAppearance = MapAppearance(rawValue: defaults.string(forKey: Keys.mapAppearance) ?? "") ?? .standard
        showInactiveTrains = defaults.object(forKey: Keys.showInactiveTrains) as? Bool ?? false
        showTrainLabels = defaults.object(forKey: Keys.showTrainLabels) as? Bool ?? true
        colorMarkersByDelay = defaults.object(forKey: Keys.colorMarkersByDelay) as? Bool ?? true
        showStations = defaults.object(forKey: Keys.showStations) as? Bool ?? true
        let stored = defaults.double(forKey: Keys.pollingInterval)
        pollingInterval = stored > 0 ? stored : 15
        recentStations = defaults.stringArray(forKey: Keys.recentStations) ?? []
        storedRecentTrains = (defaults.data(forKey: Keys.recentTrains))
            .flatMap { try? JSONDecoder().decode([RecentTrain].self, from: $0) } ?? []
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
    }
}
