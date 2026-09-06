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
        #expect(StationPins.visible(from: stations, in: wide, excluding: []).isEmpty)
        // Just inside the threshold the same station is drawn, so the gate is what excluded it.
        let narrow = region(spanDegrees: StationPins.zoomThreshold - 0.01)
        #expect(StationPins.visible(from: stations, in: narrow, excluding: []).map(\.id) == ["Cst"])
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
        #expect(StationPins.visible(from: stations, in: landscape, excluding: []).isEmpty)
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
        let visible = StationPins.visible(from: stations, in: region(), excluding: [])
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
        #expect(StationPins.visible(from: stations, in: wide, excluding: []).map(\.id) == ["Inside"])
    }

    @Test("Stations drawn as their own markers are skipped — the selection and the route's stops")
    func skipsStationsDrawnElsewhere() throws {
        let stations = try [
            station("Cst"),
            station("Sod", latitudeOffset: 0.05),
            station("Fle", latitudeOffset: 0.08),
        ]
        let visible = StationPins.visible(from: stations, in: region(), excluding: ["Cst", "Fle"])
        #expect(visible.map(\.id) == ["Sod"])
    }

    @Test("Order follows the directory, so the drawn set is stable between refreshes")
    func preservesInputOrder() throws {
        let stations = try [station("B", latitudeOffset: 0.01), station("A", latitudeOffset: -0.01)]
        #expect(StationPins.visible(from: stations, in: region(), excluding: []).map(\.id) == ["B", "A"])
    }

    @Test("A crowded dot's tap target shrinks to its neighbour, an isolated one keeps the maximum")
    func sizesTapTargetsToTheNeighbourhood() throws {
        let stations = try [
            station("Crowded"),
            station("Neighbour", latitudeOffset: 0.001),
            station("Lonely", latitudeOffset: 0.1),
        ]
        // 0.3° tall over 900pt: the two crowded stations are 3pt apart, the lonely one is not.
        let pins = StationPins.pins(from: stations, in: region(spanDegrees: 0.3), excluding: [], mapHeight: 900)
        let sizes = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0.hitSize) })
        #expect(sizes["Crowded"] == StationPins.minHitSize)
        #expect(sizes["Neighbour"] == StationPins.minHitSize)
        #expect(sizes["Lonely"] == StationPins.maxHitSize)
    }

    @Test("Two dots close together take a target no wider than the gap between them")
    func sizesTapTargetsToTheGap() throws {
        let stations = try [station("A"), station("B", latitudeOffset: 0.01)]
        // 0.3° over 900pt is 3000pt per degree, so 0.01° apart is 30pt.
        let pins = StationPins.pins(from: stations, in: region(spanDegrees: 0.3), excluding: [], mapHeight: 900)
        #expect(pins.allSatisfy { abs($0.hitSize - 30) < 0.001 })
    }

    @Test("Without a measured map height every target falls back to the dot's own size")
    func fallsBackWithoutAMapHeight() throws {
        let stations = try [station("Cst")]
        let pins = StationPins.pins(from: stations, in: region(), excluding: [], mapHeight: 0)
        #expect(pins.map(\.hitSize) == [StationPins.minHitSize])
    }
}
