import CoreLocation
import Foundation
import MapKit
@testable import Tagkollen
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
        longitudeOffset: CLLocationDegrees = 0
    ) throws -> LocatedStation {
        let json = Data(#"{"LocationSignature":"\#(signature)"}"#.utf8)
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
        let wide = region(spanDegrees: StationPins.zoomThreshold)
        #expect(StationPins.visible(from: stations, in: wide).isEmpty)
        // Just inside the threshold the same station is drawn, so the gate is what excluded it.
        let narrow = region(spanDegrees: StationPins.zoomThreshold - 0.01)
        #expect(StationPins.visible(from: stations, in: narrow).map(\.id) == ["Cst"])
    }

    @Test("A region far wider than it is tall is gated on its wider axis")
    func gatesOnTheWiderAxis() throws {
        let stations = try [station("Cst")]
        // Landscape-shaped: the latitude span alone would pass the gate, but at 59°N the longitude
        // span still covers more ground than the threshold allows.
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
        // 2° of longitude at 59.33°N covers about 1.02° worth of ground, inside the 1.5° gate — so
        // this is drawn only if the gate scales longitude instead of comparing it raw.
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

    private func pins(_ stations: [LocatedStation], marked: [String: CLLocationCoordinate2D] = [:]) -> [StationPin] {
        StationPins.pins(from: stations, in: sizingRegion, markedElsewhere: marked, mapHeight: 900)
    }

    @Test("Two dots too close to tell apart are drawn as one")
    func collapsesDotsThatWouldOverlap() throws {
        let stations = try [station("Kept"), station("Merged", latitudeOffset: 0.001)]
        // 3pt apart: drawing both would give each a target too small to hit.
        #expect(pins(stations).map(\.id) == ["Kept"])
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
        let marked = ["Selected": CLLocationCoordinate2D(
            latitude: Self.centre.latitude + 0.01,
            longitude: Self.centre.longitude
        )]
        let result = pins(stations, marked: marked)
        // Without the marker in the spacing this would claim the maximum and cover it, swallowing
        // the taps meant for it.
        #expect(result.map(\.id) == ["Ambient"])
        #expect(result.map(\.hitSize) == [30])
    }

    @Test("A marker is measured where it is drawn, not at the station's own coordinate")
    func marksAreMeasuredWhereTheyAreDrawn() throws {
        let stations = try [station("Ambient"), station("Stop", latitudeOffset: 0.1)]
        // A route stop is drawn on the rail network's node for it, which here is right next to the
        // ambient dot even though the station's own coordinate is far away.
        let marked = ["Stop": CLLocationCoordinate2D(
            latitude: Self.centre.latitude + 0.001,
            longitude: Self.centre.longitude
        )]
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
        let marked = ["G": CLLocationCoordinate2D(
            latitude: Self.centre.latitude + 0.03,
            longitude: Self.centre.longitude
        )]
        let result = pins(stations, marked: marked)
        let pointsPerDegree = 900.0 / 0.3
        let longitudeScale = cos(Self.centre.latitude * .pi / 180)
        var others = Array(marked.values)
        others.append(contentsOf: result.map(\.station.clCoordinate))
        for pin in result {
            let point = pin.station.clCoordinate
            for other in others where other.latitude != point.latitude || other.longitude != point.longitude {
                let dy = (other.latitude - point.latitude) * pointsPerDegree
                let dx = (other.longitude - point.longitude) * longitudeScale * pointsPerDegree
                #expect((dx * dx + dy * dy).squareRoot() > Double(pin.hitSize) / 2)
            }
        }
        #expect(result.count > 1)
    }

    @Test("The zoom gate applies to the drawn dots, not just the visible set")
    func pinsRespectTheZoomGate() throws {
        let stations = try [station("Cst")]
        let wide = MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: StationPins.zoomThreshold, longitudeDelta: 0.1)
        )
        #expect(StationPins.pins(from: stations, in: wide, mapHeight: 900).isEmpty)
    }

    @Test("Without a measured map height every target falls back to the dot's own size")
    func fallsBackWithoutAMapHeight() throws {
        let stations = try [station("Cst")]
        let pins = StationPins.pins(from: stations, in: region(), mapHeight: 0)
        #expect(pins.map(\.hitSize) == [StationPins.minSeparation])
    }
}
