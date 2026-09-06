import CoreLocation
import Foundation
import MapKit

/// One ambient station dot on the map, with the tap target it should get at the current camera.
struct StationPin: Identifiable, Equatable {
    let station: LocatedStation
    /// Diameter of the invisible tap target around the dot, in points.
    let hitSize: CGFloat

    var id: String {
        station.id
    }
}

/// Which stations to draw as ambient dots on the map, and how big a tap target each one can
/// safely claim. Kept out of `TrainMapView` so the rules can be tested without a live SwiftUI
/// environment.
enum StationPins {
    /// Zoomed out further than this, the dots are unreadable clutter, so none are drawn.
    static let zoomThreshold: CLLocationDegrees = 1.5
    /// The dot itself is 16pt, so a target never shrinks below it, and 44pt is as large as a
    /// target is ever worth making.
    static let minHitSize: CGFloat = 16
    static let maxHitSize: CGFloat = 44

    /// The stations worth drawing for a given camera: none at all when zoomed out past
    /// `zoomThreshold`, otherwise those inside the region — padded, so a small pan doesn't reveal
    /// a blank strip before the next refresh — minus `excluded`, which covers the selected station
    /// and the stops of a selected train's route, both of which are drawn as their own markers.
    ///
    /// The gate uses whichever axis covers more ground: a landscape iPad's region is far wider
    /// than it is tall, and gating on latitude alone would let a whole country's worth of dots in.
    static func visible(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        excluding excluded: Set<String>
    ) -> [LocatedStation] {
        let widest = max(region.span.latitudeDelta, region.span.longitudeDelta * cos(region.center.latitude * .pi / 180))
        guard widest < zoomThreshold else { return [] }
        let padded = region.padded(by: 0.25)
        return located.filter { station in
            !excluded.contains(station.id) && padded.contains(station.clCoordinate)
        }
    }

    /// The same stations, each with a tap target no wider than the distance to its nearest
    /// neighbour on screen. A fixed 44pt target covers kilometres of ground on a wide camera, and
    /// overlapping targets resolve by draw order rather than by which dot is nearer — which leaves
    /// the covered station unreachable however carefully the user aims. Sizing each target to its
    /// own neighbourhood keeps every visible dot tappable.
    static func pins(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        excluding excluded: Set<String>,
        mapHeight: CGFloat
    ) -> [StationPin] {
        let stations = visible(from: located, in: region, excluding: excluded)
        guard mapHeight > 0, region.span.latitudeDelta > 0 else {
            return stations.map { StationPin(station: $0, hitSize: minHitSize) }
        }
        let pointsPerDegree = Double(mapHeight) / region.span.latitudeDelta
        let longitudeScale = cos(region.center.latitude * .pi / 180)
        return stations.map { station in
            var nearest = Double.greatestFiniteMagnitude
            for other in stations where other.id != station.id {
                let dy = (other.coordinate.latitude - station.coordinate.latitude) * pointsPerDegree
                let dx = (other.coordinate.longitude - station.coordinate.longitude) * longitudeScale * pointsPerDegree
                nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
            }
            let size = nearest.isFinite ? min(Double(maxHitSize), max(Double(minHitSize), nearest)) : Double(maxHitSize)
            return StationPin(station: station, hitSize: CGFloat(size))
        }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
