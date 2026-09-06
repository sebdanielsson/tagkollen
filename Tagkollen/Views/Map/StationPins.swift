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
    /// The dot's own diameter. Two dots closer than this on screen are one blob, and only one of
    /// them is drawn; it is also the smallest tap target any dot ends up with.
    static let minSeparation: CGFloat = 16
    /// As large as a tap target is ever worth making.
    static let maxHitSize: CGFloat = 44

    /// Every station on screen for a given camera: none at all when zoomed out past
    /// `zoomThreshold`, otherwise those inside the region, padded so a small pan doesn't reveal a
    /// blank strip before the next refresh.
    ///
    /// The gate uses whichever axis covers more ground: a landscape iPad's region is far wider
    /// than it is tall, and gating on latitude alone would let a whole country's worth of dots in.
    static func visible(from located: [LocatedStation], in region: MKCoordinateRegion) -> [LocatedStation] {
        let widest = max(region.span.latitudeDelta, region.span.longitudeDelta * cos(region.center.latitude * .pi / 180))
        guard widest < zoomThreshold else { return [] }
        let padded = region.padded(by: 0.25)
        return located.filter { padded.contains($0.clCoordinate) }
    }

    /// The stations to draw as ambient dots, each with a tap target sized to its surroundings.
    ///
    /// `markedElsewhere` maps a station's signature to the point its own marker is drawn at — the
    /// selected station, and the stops of a selected train's route. Those get no ambient dot, but
    /// they still occupy the map, so they take part in the spacing: a target that ignored them
    /// would grow wide enough to cover one and swallow the taps meant for it. Note the point, not
    /// the station's directory coordinate: a route stop is drawn on the rail network's node for
    /// it, which can be a hundred metres away.
    ///
    /// Two rules keep every drawn dot tappable. A dot closer than `minSeparation` to something
    /// already on the map isn't drawn at all — at that distance it is the same blob, and drawing
    /// both means two dots that each swallow the other's taps. What remains is then given a target
    /// no wider than the gap to its nearest neighbour, so targets meet without covering each
    /// other's centres, and never smaller than the dot itself.
    ///
    /// A station that loses its dot this way keeps a tappable marker whenever it is the one that
    /// was marked, and is drawn again as soon as the camera separates the two.
    static func pins(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        markedElsewhere: [String: CLLocationCoordinate2D] = [:],
        mapHeight: CGFloat
    ) -> [StationPin] {
        let drawn = visible(from: located, in: region).filter { markedElsewhere[$0.id] == nil }
        let scale = pointsPerMapPoint(in: region, mapHeight: mapHeight)
        guard scale > 0 else {
            return drawn.map { StationPin(station: $0, hitSize: minSeparation) }
        }
        func distance(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() * scale
        }

        var occupied = markedElsewhere.values.map(MKMapPoint.init)
        var chosen: [Chosen] = []
        for entry in collapseOrder(drawn) {
            let point = MKMapPoint(entry.station.clCoordinate)
            guard !occupied.contains(where: { distance($0, point) < Double(minSeparation) }) else { continue }
            chosen.append(Chosen(station: entry.station, order: entry.order, index: occupied.count))
            occupied.append(point)
        }
        return chosen.sorted { $0.order < $1.order }.map { entry in
            let point = MKMapPoint(entry.station.clCoordinate)
            var nearest = Double.infinity
            for (index, other) in occupied.enumerated() where index != entry.index {
                nearest = min(nearest, distance(other, point))
            }
            // Rounded to whole points, which can overlap two targets by up to half a point — far
            // too little to put either dot's centre inside the other's target.
            return StationPin(station: entry.station, hitSize: CGFloat(min(Double(maxHitSize), nearest).rounded()))
        }
    }

    /// A station that survived the collapse: `order` is its place in the directory, so the drawn
    /// set can be handed back in that order, and `index` is where its point sits in `occupied`, so
    /// the sizing pass can skip measuring it against itself.
    private struct Chosen {
        let station: LocatedStation
        let order: Int
        let index: Int
    }

    /// Screen points per Mercator map point for a camera. Distances are measured in map points
    /// rather than in degrees so that two stations' spacing doesn't depend on where the camera
    /// happens to be centred, which would make a pan alone re-decide which dots are drawn.
    private static func pointsPerMapPoint(in region: MKCoordinateRegion, mapHeight: CGFloat) -> Double {
        guard mapHeight > 0, region.span.latitudeDelta > 0 else { return 0 }
        let half = region.span.latitudeDelta / 2
        let north = MKMapPoint(CLLocationCoordinate2D(latitude: min(85, region.center.latitude + half), longitude: region.center.longitude))
        let south = MKMapPoint(CLLocationCoordinate2D(
            latitude: max(-85, region.center.latitude - half),
            longitude: region.center.longitude
        ))
        let height = abs(south.y - north.y)
        return height > 0 ? Double(mapHeight) / height : 0
    }

    /// The order the collapse considers stations in, so that when two dots are too close to draw
    /// both, the one that survives is the one a user is likelier to be looking for: the bigger
    /// station, measured by how many platforms it advertises. Ties keep the directory's own order,
    /// so the result is deterministic. Without this the survivor came down to alphabetical order,
    /// which kept Karlberg over Stockholm C and Gamlestaden over Göteborg C.
    private static func collapseOrder(_ stations: [LocatedStation]) -> [(station: LocatedStation, order: Int)] {
        stations.enumerated()
            .map { (station: $0.element, order: $0.offset) }
            .sorted { lhs, rhs in
                let left = lhs.station.station.platformLine?.count ?? 0
                let right = rhs.station.station.platformLine?.count ?? 0
                return left == right ? lhs.order < rhs.order : left > right
            }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
