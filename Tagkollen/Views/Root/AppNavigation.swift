import Foundation
import SwiftUI

/// Cross-tab navigation state: which tab is showing and any pending "show this train on the map".
@MainActor
@Observable
final class AppNavigation {
    enum Tab: Hashable {
        case map, favorites, search
    }

    var selectedTab: Tab = .map
    /// Set by other screens; the map consumes it, centres on the train and opens its detail.
    var pendingMapFocus: TrainKey?
    /// A station board to open, by location signature. Set from widget deep links.
    var pendingStationSignature: String?

    func showOnMap(_ key: TrainKey) {
        pendingMapFocus = key
        selectedTab = .map
    }

    func showStation(_ signature: String) {
        pendingStationSignature = signature
        selectedTab = .search
    }

    /// Handles `tagkollen://train/<ident>@<yyyy-MM-dd>`, `tagkollen://train/<ident>` (today) and
    /// `tagkollen://station/<signature>`.
    func handle(_ url: URL) {
        guard url.scheme == "tagkollen" else { return }
        let raw = url.pathComponents.dropFirst().joined(separator: "/")
        switch url.host() {
        case "train":
            guard !raw.isEmpty else { return }
            if let key = TrainKey(id: raw) {
                showOnMap(key)
            } else {
                showOnMap(.today(raw))
            }
        case "station":
            guard !raw.isEmpty else { return }
            showStation(raw)
        default:
            break
        }
    }
}
