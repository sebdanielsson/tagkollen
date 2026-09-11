import CoreLocation
import Foundation
import MapKit
@testable import Tagradar
import Testing
import TrafikverketKit

/// `StationPins` decides which station dots the map draws and how big a tap target each one gets,
/// so the rules it encodes — the zoom gate, the padded visible region, skipping stations that have
/// their own marker, and sizing targets to the local crowding — are pinned here.
@Suite("Station pins")
struct StationPinsTests {
    private static let centre = CLLocationCoordinate2D(latitude: 59.33, longitude: 18.06)

    private func region(spanDegrees: CLLocationDegrees = 0.4) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
    }

    private func station(
        _ signature: String,
        latitudeOffset: CLLocationDegrees = 0,
        longitudeOffset: CLLocationDegrees = 0,
        platforms: Int? = nil
    ) throws -> LocatedStation {
        let field = platforms.map { count in
            let lines = (0 ..< count).map { "\"\($0 + 1)\"" }.joined(separator: ",")
            return #","PlatformLine":[\#(lines)]"#
        } ?? ""
        let json = Data(#"{"LocationSignature":"\#(signature)"\#(field)}"#.utf8)
        let decoded = try JSONDecoder.trafikverket.decode(TrainStation.self, from: json)
        return LocatedStation(
            station: decoded,
            coordinate: Coordinate(
                latitude: Self.centre.latitude + latitudeOffset,
                longitude: Self.centre.longitude + longitudeOffset
            )
        )
    }

    @Test("No dots at all when zoomed out past the threshold")
    func nothingWhenZoomedOut() throws {
        let stations = try [station("Cst")]
        // 1.6° of latitude at 59.33°N is past the threshold; 1.4° is inside it.
        #expect(StationPins.visible(from: stations, in: region(spanDegrees: 1.6)).isEmpty)
        #expect(StationPins.visible(from: stations, in: region(spanDegrees: 1.4)).map(\.id) == ["Cst"])
    }

    @Test("The gate follows the zoom, not the camera's latitude")
    func gateFollowsTheZoomNotTheLatitude() throws {
        // The same zoom covers fewer degrees of latitude the further north the camera is. A gate
        // measured in degrees would let 1.4° through at both latitudes; measured in map points,
        // 1.4° up at 68°N is a much wider view and is correctly shut out.
        let arctic = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 68, longitude: 18.06),
            span: MKCoordinateSpan(latitudeDelta: 1.4, longitudeDelta: 1.4)
        )
        #expect(try StationPins.visible(from: [station("Abk")], in: arctic).isEmpty)
    }

    @Test("A region far wider than it is tall is gated on its wider axis")
    func gatesOnTheWiderAxis() throws {
        let stations = try [station("Cst")]
        // Landscape-shaped: the latitude span alone would pass the gate, but the longitude span
        // covers far more ground than the threshold allows.
        let landscape = MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 4.0)
        )
        #expect(StationPins.visible(from: stations, in: landscape).isEmpty)
    }

    @Test("Only stations inside the padded region are drawn")
    func filtersToPaddedRegion() throws {
        // Half the span is 0.2 and the 25% padding extends the reach to exactly 0.25, so these two
        // straddle the boundary closely enough to pin the padding fraction itself.
        let stations = try [
            station("Inside", latitudeOffset: 0.1),
            station("InPadding", latitudeOffset: 0.249),
            station("Outside", latitudeOffset: 0.251),
        ]
        let visible = StationPins.visible(from: stations, in: region())
        #expect(visible.map(\.id) == ["Inside", "InPadding"])
    }

    @Test("Longitude is filtered on its own axis, not the latitude span")
    func filtersOnLongitudeToo() throws {
        // Deliberately not square: half the longitude span is 0.05, padded to 0.0625.
        let wide = MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.1)
        )
        let stations = try [
            station("Inside", longitudeOffset: 0.05),
            station("Outside", longitudeOffset: 0.08),
        ]
        #expect(StationPins.visible(from: stations, in: wide).map(\.id) == ["Inside"])
    }

    @Test("A degree of longitude counts for less than a degree of latitude this far north")
    func gateScalesLongitudeByLatitude() throws {
        let stations = try [station("Cst")]
        // 2° of longitude is narrower on the ground than 2° of latitude at 59°N, and lands inside
        // the gate — so this is drawn only if longitude is projected rather than compared raw.
        let wide = MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 2.0)
        )
        #expect(StationPins.visible(from: stations, in: wide).map(\.id) == ["Cst"])
    }

    @Test("Order follows the directory, so the drawn set is stable between refreshes")
    func preservesInputOrder() throws {
        let stations = try [station("B", latitudeOffset: 0.01), station("A", latitudeOffset: -0.01)]
        #expect(StationPins.visible(from: stations, in: region()).map(\.id) == ["B", "A"])
    }

    /// Deliberately not square, so a sizing bug that scaled by the longitude span instead of the
    /// latitude one would show up: 0.3° tall over 900pt is 3000pt per degree of latitude.
    private var sizingRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: Self.centre, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.6))
    }

    /// A marker taking up as much room as an ambient dot, unless a test needs a bigger one.
    private func marker(latitudeOffset: CLLocationDegrees = 0, radius: CGFloat = StationPins.dotRadius) -> MapMarker {
        MapMarker(
            coordinate: CLLocationCoordinate2D(
                latitude: Self.centre.latitude + latitudeOffset,
                longitude: Self.centre.longitude
            ),
            radius: radius
        )
    }

    private func pins(_ stations: [LocatedStation], marked: [String: MapMarker] = [:]) -> [StationPin] {
        StationPins.layout(from: stations, in: sizingRegion, markedElsewhere: marked, mapHeight: 900).pins
    }

    @Test("Two dots too close to tell apart are drawn as one")
    func collapsesDotsThatWouldOverlap() throws {
        let stations = try [station("Kept"), station("Merged", latitudeOffset: 0.001)]
        // 3pt apart: drawing both would give each a target too small to hit.
        #expect(pins(stations).map(\.id) == ["Kept"])
    }

    @Test("The bigger station survives a collapse, whatever its place in the directory")
    func collapseKeepsTheBiggerStation() throws {
        // Alphabetically "Karlberg" precedes "Stockholm C", and a plain first-come pass kept it.
        let stations = try [
            station("Karlberg", platforms: 4),
            station("Stockholm C", latitudeOffset: 0.001, platforms: 34),
        ]
        #expect(pins(stations).map(\.id) == ["Stockholm C"])
    }

    @Test("A station that reports no platforms ranks last")
    func unknownPlatformCountRanksLast() throws {
        // The deliberate trade-off: promoting an unknown count put all 130 of them ahead of real
        // single-platform stations, which cost more than it won (see `StationPins.platformCount`).
        let stations = try [
            station("Lövliden", platforms: nil),
            station("Vilhelmina norra", latitudeOffset: 0.001, platforms: 1),
        ]
        #expect(pins(stations).map(\.id) == ["Vilhelmina norra"])
    }

    @Test("Dots come back in directory order, whatever order the collapse considered them in")
    func keepsDirectoryOrder() throws {
        let stations = try [
            station("A", platforms: 1),
            station("B", latitudeOffset: 0.02, platforms: 9),
            station("C", latitudeOffset: 0.04, platforms: 5),
        ]
        #expect(pins(stations).map(\.id) == ["A", "B", "C"])
    }

    @Test("A dot exactly a dot's width away is still its own dot")
    func keepsDotsAtTheSeparationLimit() throws {
        let stations = try [station("A"), station("B", latitudeOffset: 0.006)]
        // 18pt apart, past the 16pt limit, so both are drawn and each target is the whole gap.
        #expect(pins(stations).map(\.hitSize) == [18, 18])
    }

    @Test("An isolated dot keeps the maximum target")
    func isolatedDotKeepsTheMaximum() throws {
        let stations = try [station("Lonely"), station("Far", latitudeOffset: 0.1)]
        #expect(pins(stations).map(\.hitSize) == [StationPins.maxHitSize, StationPins.maxHitSize])
    }

    @Test("Two dots close together take a target no wider than the gap between them")
    func sizesTapTargetsToTheGap() throws {
        let stations = try [station("A"), station("B", latitudeOffset: 0.01)]
        // 0.01° of latitude at 3000pt per degree is 30pt — the whole gap, not half of it, so the
        // two targets meet without covering each other's centres.
        #expect(pins(stations).map(\.hitSize) == [30, 30])
    }

    @Test("East-west spacing is scaled by latitude, so it isn't overstated this far north")
    func sizesTapTargetsAcrossLongitude() throws {
        let stations = try [station("A"), station("B", longitudeOffset: 0.02)]
        // 0.02° of longitude at 59.33°N is about half as wide as 0.02° of latitude: 31pt, not 60.
        #expect(pins(stations).map(\.hitSize) == [31, 31])
    }

    @Test("A station with a marker of its own gets no dot, but still bounds its neighbours")
    func markedStationsBoundTheirNeighbours() throws {
        let stations = try [station("Ambient"), station("Selected", latitudeOffset: 0.01)]
        let marked = ["Selected": marker(latitudeOffset: 0.01)]
        let layout = StationPins.layout(from: stations, in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        // Without the marker in the spacing the dot would claim the maximum and cover it,
        // swallowing the taps meant for it — and the marker is bounded by the dot in turn.
        #expect(layout.pins.map(\.id) == ["Ambient"])
        #expect(layout.pins.map(\.hitSize) == [30])
        #expect(layout.markerHitSizes == ["Selected": 30])
    }

    @Test("A marker is measured where it is drawn, not at the station's own coordinate")
    func marksAreMeasuredWhereTheyAreDrawn() throws {
        let stations = try [station("Ambient"), station("Stop", latitudeOffset: 0.1)]
        // A route stop is drawn on the rail network's node for it, which here is right next to the
        // ambient dot even though the station's own coordinate is far away.
        let marked = ["Stop": marker(latitudeOffset: 0.001)]
        #expect(pins(stations, marked: marked).isEmpty)
    }

    @Test("No drawn dot's centre falls inside another's tap target")
    func targetsNeverCoverAnotherCentre() throws {
        // A deliberately awkward cluster: pairs at 3pt, 18pt, 30pt and far apart, plus a marker.
        let stations = try [
            station("A"),
            station("B", latitudeOffset: 0.001),
            station("C", latitudeOffset: 0.006),
            station("D", latitudeOffset: 0.016),
            station("E", longitudeOffset: 0.02),
            station("F", latitudeOffset: 0.1, longitudeOffset: 0.1),
        ]
        let marked = ["G": marker(latitudeOffset: 0.03)]
        let layout = StationPins.layout(from: stations, in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        let result = layout.pins
        let pointsPerDegree = 900.0 / 0.3
        let longitudeScale = cos(Self.centre.latitude * .pi / 180)
        // Every drawn thing, dots and markers alike, each with the target it was given.
        struct Drawn {
            let point: CLLocationCoordinate2D
            let hitSize: CGFloat
            let isMarker: Bool
        }
        var drawn = result.map { Drawn(point: $0.station.clCoordinate, hitSize: $0.hitSize, isMarker: false) }
        drawn += marked.compactMap { signature, point in
            layout.markerHitSizes[signature].map { Drawn(point: point.coordinate, hitSize: $0, isMarker: true) }
        }
        for (index, thing) in drawn.enumerated() {
            for (otherIndex, other) in drawn.enumerated() where otherIndex != index {
                // Two markers may reach into each other — neither can be dropped to make room.
                guard !(thing.isMarker && other.isMarker) else { continue }
                let dy = (other.point.latitude - thing.point.latitude) * pointsPerDegree
                let dx = (other.point.longitude - thing.point.longitude) * longitudeScale * pointsPerDegree
                #expect((dx * dx + dy * dy).squareRoot() > Double(thing.hitSize) / 2)
            }
        }
        #expect(result.count > 1)
        // Every drawn dot is worth drawing: a target no smaller than the dot itself. Without this
        // the test would pass with every target shrunk to a point nobody can hit.
        #expect(result.allSatisfy { $0.hitSize >= StationPins.minSeparation })
        #expect(result.allSatisfy { $0.hitSize <= StationPins.maxHitSize })
        #expect(result.contains { $0.hitSize == StationPins.maxHitSize })
        // The markers get real targets too, never one too small to hit.
        #expect(layout.markerHitSizes.count == marked.count)
        #expect(layout.markerHitSizes.values.allSatisfy { $0 >= StationPins.minSeparation })
    }

    @Test("The zoom gate applies to the drawn dots, not just the visible set")
    func pinsRespectTheZoomGate() throws {
        let stations = try [station("Cst")]
        // 1.6° of latitude at this camera is past the gate; the threshold itself is in map points.
        let wide = MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 0.1)
        )
        #expect(StationPins.layout(from: stations, in: wide, mapHeight: 900).pins.isEmpty)
    }

    @Test("Two markers close together get targets that don't cover each other either")
    func sizesMarkersAgainstEachOther() {
        // Two consecutive route stops 18pt apart: each keeps its own 18pt target rather than the
        // full width, which would put each one's centre inside the other's.
        let marked = ["First": marker(), "Second": marker(latitudeOffset: 0.006)]
        let layout = StationPins.layout(from: [], in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        #expect(layout.markerHitSizes == ["First": 18, "Second": 18])
    }

    @Test("A marker's target is bounded by the nearest ambient dot, not only by other markers")
    func sizesMarkersAgainstDots() throws {
        let stations = try [station("Ambient", latitudeOffset: 0.01)]
        let marked = ["Stop": marker()]
        let layout = StationPins.layout(from: stations, in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        // The only other thing on the map is a dot 30pt away, so the marker gets 30, not the cap.
        #expect(layout.markerHitSizes == ["Stop": 30])
        #expect(layout.pins.map(\.hitSize) == [30])
    }

    @Test("Two markers too close to size apart still keep a target big enough to hit")
    func markersKeepAUsableTarget() {
        // Consecutive stops a few points apart: markers are never dropped, so both keep the dot's
        // own width rather than shrinking to something nobody can tap.
        let marked = ["First": marker(), "Second": marker(latitudeOffset: 0.001)]
        let layout = StationPins.layout(from: [], in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        #expect(layout.markerHitSizes == ["First": StationPins.minSeparation, "Second": StationPins.minSeparation])
    }

    @Test("A wider marker clears more room than a dot does")
    func widerMarkersClearMoreRoom() throws {
        let stations = try [station("Ambient", latitudeOffset: 0.006)]
        // 18pt away: clear of another dot (8 + 8), but not of the selected station's marker,
        // which is 28pt across and would be drawn over it.
        #expect(pins(stations, marked: ["Small": marker()]).map(\.id) == ["Ambient"])
        let big = ["Selected": marker(radius: StationMarker.selectedSize / 2)]
        #expect(pins(stations, marked: big).isEmpty)
    }

    @Test("A lone marker gets the maximum target")
    func sizesALoneMarker() {
        let marked = ["Only": marker()]
        let layout = StationPins.layout(from: [], in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
        #expect(layout.markerHitSizes == ["Only": StationPins.maxHitSize])
    }

    @Test("Without a measured map height every target falls back to the dot's own size")
    func fallsBackWithoutAMapHeight() throws {
        let stations = try [station("Cst")]
        let pins = StationPins.layout(from: stations, in: region(), mapHeight: 0).pins
        #expect(pins.map(\.hitSize) == [StationPins.minSeparation])
    }
}
