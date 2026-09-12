import MapKit
import SwiftUI
import TrafikverketKit

/// The map's durable state — camera, selection and the bottom card's trail — kept outside
/// `MapScreen` so it survives that view being rebuilt.
///
/// `RootView` hosts `MapScreen` in two structurally different places: bare in the iPhone layout
/// and inside a `Tab` in the tabbed one. A change of horizontal size class therefore gives SwiftUI
/// a new view identity and discards whatever `@State` the old `MapScreen` held. That flip happens
/// whenever an iPhone Plus or Max rotates to landscape, and on iPhone Duo every time the device
/// opens or closes. Owning this object in `RootView` and reading it through the environment, the
/// way `AppNavigation` already is, keeps the camera where the user left it and the selected train
/// selected across the swap.
@MainActor
@Observable
final class MapState {
    static let swedenRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 14.5, longitudeDelta: 14.5)
    )

    var camera: MapCameraPosition = .region(MapState.swedenRegion)
    var visibleRegion: MKCoordinateRegion = MapState.swedenRegion
    var selectedTrainID: String?
    var selectedKey: TrainKey?
    var selectedStation: TrainStation?

    /// The iPhone card's navigation trail and its typed shadow, kept in lockstep with every push —
    /// see `MapNavigationStack`. Preserved across a size-class change too, so folding the device
    /// back to the cover display returns to the board or detail the card was showing.
    var sheetPath = NavigationPath()
    var navigationStack = MapNavigationStack()
    var sheetDetent: PresentationDetent = .medium

    /// A focus request `MapScreen` deferred because live positions hadn't arrived yet. Kept here
    /// rather than in `AppNavigation.pendingMapFocus`, which means "something outside the map
    /// asked for this" and resets the card's trail — a retry of the map's own must not do that.
    var deferredFocus: DeferredFocus?

    struct DeferredFocus {
        let key: TrainKey
        let pushesPath: Bool
    }
}
