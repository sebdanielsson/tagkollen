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

    func showOnMap(_ key: TrainKey) {
        pendingMapFocus = key
        selectedTab = .map
    }

    /// Handles `tagkollen://train/<ident>@<yyyy-MM-dd>` and `tagkollen://train/<ident>` (today).
    func handle(_ url: URL) {
        guard url.scheme == "tagkollen", url.host() == "train" else { return }
        let raw = url.pathComponents.dropFirst().joined(separator: "/")
        guard !raw.isEmpty else { return }
        if let key = TrainKey(id: raw) {
            showOnMap(key)
        } else {
            showOnMap(.today(raw))
        }
    }
}
