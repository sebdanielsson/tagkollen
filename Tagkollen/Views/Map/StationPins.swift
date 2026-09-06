import CoreLocation
import MapKit

/// Which stations to draw as ambient dots on the map, kept out of `TrainMapView` so the rules can
/// be tested without a live SwiftUI environment.
enum StationPins {
    /// Zoomed out further than this, the dots are unreadable clutter, so none are drawn. Matches
    /// the zoom at which stop names become legible on a selected train's route.
    static let zoomThreshold: CLLocationDegrees = 1.5

    /// The stations worth drawing for a given camera: none at all when zoomed out past
    /// `zoomThreshold`, otherwise those inside the region — padded, so a small pan doesn't reveal
    /// a blank strip before the next refresh — minus the selected one, which is drawn separately
    /// as a larger marker.
    static func visible(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        excluding selected: String?
    ) -> [LocatedStation] {
        guard region.span.latitudeDelta < zoomThreshold else { return [] }
        let padded = region.padded(by: 0.25)
        return located.filter { station in
            station.id != selected && padded.contains(station.clCoordinate)
        }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
