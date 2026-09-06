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
    /// 44pt is as large as a tap target is ever worth making.
    static let maxHitSize: CGFloat = 44
    /// Used only when the map's size isn't known yet and neighbours can't be measured: the size of
    /// the dot itself.
    static let fallbackHitSize: CGFloat = 16

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
    /// neighbour on screen. A fixed target covers kilometres of ground on a wide camera, and
    /// overlapping targets resolve by draw order rather than by which dot is nearer — which leaves
    /// the covered station unreachable however carefully the user aims. Sized this way two targets
    /// are tangent at worst, so every drawn dot stays reachable.
    static func pins(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        excluding excluded: Set<String>,
        mapHeight: CGFloat
    ) -> [StationPin] {
        // Neighbours are measured against everything drawn in the region, the excluded stations
        // included: those still have a marker of their own, and a target that ignored them would
        // grow wide enough to cover one and swallow taps meant for it.
        let drawn = visible(from: located, in: region, excluding: [])
        let stations = drawn.filter { !excluded.contains($0.id) }
        guard mapHeight > 0, region.span.latitudeDelta > 0 else {
            return stations.map { StationPin(station: $0, hitSize: fallbackHitSize) }
        }
        let pointsPerDegree = Double(mapHeight) / region.span.latitudeDelta
        let longitudeScale = cos(region.center.latitude * .pi / 180)
        return stations.map { station in
            var nearest = Double.infinity
            for other in drawn where other.id != station.id {
                let dy = (other.coordinate.latitude - station.coordinate.latitude) * pointsPerDegree
                let dx = (other.coordinate.longitude - station.coordinate.longitude) * longitudeScale * pointsPerDegree
                nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
            }
            // Deliberately no lower bound: a floor would put the centres of two dots a few points
            // apart back inside each other's target, which is the overlap this exists to avoid.
            // Two dots that close are one blob at this zoom anyway — the user has to zoom in.
            // Rounded to whole points so a metre of panning doesn't count as a changed set.
            return StationPin(station: station, hitSize: CGFloat(min(Double(maxHitSize), max(1, nearest)).rounded()))
        }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
