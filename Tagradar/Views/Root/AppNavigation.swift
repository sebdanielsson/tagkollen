import Foundation
import SwiftUI

/// Requests from outside the map — widget deep links, launch arguments — for the map to show
/// something. The map consumes each one and clears it.
@MainActor
@Observable
final class AppNavigation {
    /// A train to centre on and open the detail of.
    var pendingMapFocus: TrainKey?
    /// A station board to open, by location signature.
    var pendingStationSignature: String?

    func showOnMap(_ key: TrainKey) {
        pendingMapFocus = key
    }

    func showStation(_ signature: String) {
        pendingStationSignature = signature
    }

    /// Handles `tagradar://train/<ident>@<yyyy-MM-dd>`, `tagradar://train/<ident>` (today) and
    /// `tagradar://station/<signature>`.
    func handle(_ url: URL) {
        guard url.scheme == "tagradar" else { return }
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
