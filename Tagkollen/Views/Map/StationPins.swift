import CoreLocation
import Foundation
import MapKit

/// Everything the map needs to draw and hit-test stations at the current camera.
struct StationLayout: Equatable {
    /// The ambient dots, in directory order.
    var pins: [StationPin] = []
    /// Tap targets for the stations the map draws its own marker for — the selected train's stops.
    /// Sized in the same pass as the dots, so no two targets on the map cover each other.
    var markerHitSizes: [String: CGFloat] = [:]
}

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
    /// Zoomed out further than this, the dots are unreadable clutter, so none are drawn. Measured
    /// in Mercator map points, the unit `MKMapPoint` uses, rather than in degrees: a degree of
    /// latitude covers more map points the further north the camera is, so a gate in degrees
    /// tracks the camera rather than the zoom, and a pure pan could switch every dot on the map
    /// off. Worth about 1.5° of latitude, or 165km, at Swedish latitudes.
    static let zoomThreshold: Double = 2_193_121
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
        guard mapSpan(of: region) < zoomThreshold else { return [] }
        let padded = region.padded(by: 0.25)
        return located.filter { padded.contains($0.clCoordinate) }
    }

    /// The wider of a region's two axes in Mercator map points. Longitude counts because a
    /// landscape iPad's region is far wider than it is tall; Mercator already accounts for a
    /// degree of longitude covering less ground than a degree of latitude this far north.
    private static func mapSpan(of region: MKCoordinateRegion) -> Double {
        max(mapHeight(of: region), region.span.longitudeDelta / 360 * MKMapSize.world.width)
    }

    private static func mapHeight(of region: MKCoordinateRegion) -> Double {
        let half = region.span.latitudeDelta / 2
        let north = MKMapPoint(CLLocationCoordinate2D(
            latitude: min(85, region.center.latitude + half),
            longitude: region.center.longitude
        ))
        let south = MKMapPoint(CLLocationCoordinate2D(
            latitude: max(-85, region.center.latitude - half),
            longitude: region.center.longitude
        ))
        return abs(south.y - north.y)
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
    static func layout(
        from located: [LocatedStation],
        in region: MKCoordinateRegion,
        markedElsewhere: [String: CLLocationCoordinate2D] = [:],
        mapHeight: CGFloat
    ) -> StationLayout {
        let drawn = visible(from: located, in: region).filter { markedElsewhere[$0.id] == nil }
        let scale = pointsPerMapPoint(in: region, mapHeight: mapHeight)
        guard scale > 0 else {
            return StationLayout(
                pins: drawn.map { StationPin(station: $0, hitSize: minSeparation) },
                markerHitSizes: markedElsewhere.mapValues { _ in minSeparation }
            )
        }
        func distance(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() * scale
        }

        // The markers the map draws itself come first: they are on the map whatever happens, so
        // the ambient dots work around them rather than the other way round.
        let marked = markedElsewhere.map { (signature: $0.key, point: MKMapPoint($0.value)) }
        var occupied = marked.map(\.point)
        var chosen: [Chosen] = []
        for entry in collapseOrder(drawn) {
            let point = MKMapPoint(entry.station.clCoordinate)
            guard !occupied.contains(where: { distance($0, point) < Double(minSeparation) }) else { continue }
            chosen.append(Chosen(station: entry.station, order: entry.order, index: occupied.count))
            occupied.append(point)
        }

        /// A target no wider than the gap to the nearest other marker or dot. Rounded to whole
        /// points, which can overlap two targets by up to half a point — far too little to put
        /// either centre inside the other's target.
        func hitSize(at index: Int) -> CGFloat {
            let point = occupied[index]
            var nearest = Double.infinity
            for (other, otherPoint) in occupied.enumerated() where other != index {
                nearest = min(nearest, distance(otherPoint, point))
            }
            return CGFloat(min(Double(maxHitSize), nearest).rounded())
        }
        return StationLayout(
            pins: chosen.sorted { $0.order < $1.order }
                .map { StationPin(station: $0.station, hitSize: hitSize(at: $0.index)) },
            markerHitSizes: Dictionary(
                uniqueKeysWithValues: marked.enumerated().map { ($0.element.signature, hitSize(at: $0.offset)) }
            )
        )
    }

    /// How big a station is, for deciding which dot survives a collapse. A station that reports no
    /// platforms at all — 130 of them, including every foreign one — is unknown rather than tiny,
    /// so it ranks mid-table instead of sinking below every halt with a single platform.
    private static func platformCount(_ station: LocatedStation) -> Int {
        station.station.platformLine?.count ?? 2
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
        let height = self.mapHeight(of: region)
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
                let left = platformCount(lhs.station)
                let right = platformCount(rhs.station)
                return left == right ? lhs.order < rhs.order : left > right
            }
    }
}

extension LocatedStation {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
