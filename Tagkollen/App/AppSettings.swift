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

    var pollingInterval: TimeInterval {
        didSet { defaults.set(pollingInterval, forKey: Keys.pollingInterval) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let mapAppearance = "settings.mapAppearance"
        static let showInactiveTrains = "settings.showInactiveTrains"
        static let showTrainLabels = "settings.showTrainLabels"
        static let colorMarkersByDelay = "settings.colorMarkersByDelay"
        static let pollingInterval = "settings.pollingInterval"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mapAppearance = MapAppearance(rawValue: defaults.string(forKey: Keys.mapAppearance) ?? "") ?? .standard
        showInactiveTrains = defaults.object(forKey: Keys.showInactiveTrains) as? Bool ?? false
        showTrainLabels = defaults.object(forKey: Keys.showTrainLabels) as? Bool ?? true
        colorMarkersByDelay = defaults.object(forKey: Keys.colorMarkersByDelay) as? Bool ?? true
        let stored = defaults.double(forKey: Keys.pollingInterval)
        pollingInterval = stored > 0 ? stored : 15
    }
}
