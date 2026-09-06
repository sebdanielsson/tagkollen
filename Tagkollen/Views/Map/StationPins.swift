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
    static func pins(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        markedElsewhere: [String: CLLocationCoordinate2D] = [:],
        mapHeight: CGFloat
    ) -> [StationPin] {
        let drawn = visible(from: located, in: region).filter { markedElsewhere[$0.id] == nil }
        guard mapHeight > 0, region.span.latitudeDelta > 0 else {
            return drawn.map { StationPin(station: $0, hitSize: minSeparation) }
        }
        let pointsPerDegree = Double(mapHeight) / region.span.latitudeDelta
        let longitudeScale = cos(region.center.latitude * .pi / 180)
        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let dy = (a.latitude - b.latitude) * pointsPerDegree
            let dx = (a.longitude - b.longitude) * longitudeScale * pointsPerDegree
            return (dx * dx + dy * dy).squareRoot()
        }

        var occupied = Array(markedElsewhere.values)
        var chosen: [(station: LocatedStation, index: Int)] = []
        for station in drawn {
            let point = station.clCoordinate
            guard !occupied.contains(where: { distance($0, point) < Double(minSeparation) }) else { continue }
            chosen.append((station, occupied.count))
            occupied.append(point)
        }
        return chosen.map { entry in
            let point = entry.station.clCoordinate
            var nearest = Double.infinity
            for (index, other) in occupied.enumerated() where index != entry.index {
                nearest = min(nearest, distance(other, point))
            }
            // Rounded to whole points so a metre of panning doesn't count as a changed set. That
            // can overlap two targets by up to half a point, which is far too little to put either
            // dot's centre inside the other's target.
            return StationPin(station: entry.station, hitSize: CGFloat(min(Double(maxHitSize), nearest).rounded()))
        }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
