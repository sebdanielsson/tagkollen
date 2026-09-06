import CoreLocation
import Foundation
import MapKit
@testable import Tagkollen
import Testing
import TrafikverketKit

/// `StationPins.visible` decides which station dots the map draws, so the rules it encodes — the
/// zoom gate, the padded visible region, and skipping the selected station — are pinned here.
@Suite("Station pins")
struct StationPinsTests {
    private static let centre = CLLocationCoordinate2D(latitude: 59.33, longitude: 18.06)

    /// Half a degree of latitude tall, so the region reaches 0.2° from its centre and the 25%
    /// padding extends that to 0.25°.
    private func region(spanDegrees: CLLocationDegrees = 0.4) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: Self.centre,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
    }

    private func station(_ signature: String, latitudeOffset: CLLocationDegrees) throws -> LocatedStation {
        let json = Data(#"{"LocationSignature":"\#(signature)"}"#.utf8)
        let decoded = try JSONDecoder.trafikverket.decode(TrainStation.self, from: json)
        return LocatedStation(
            station: decoded,
            coordinate: Coordinate(latitude: Self.centre.latitude + latitudeOffset, longitude: Self.centre.longitude)
        )
    }

    @Test("No dots at all when zoomed out past the threshold")
    func nothingWhenZoomedOut() throws {
        let stations = try [station("Cst", latitudeOffset: 0)]
        let wide = region(spanDegrees: StationPins.zoomThreshold)
        #expect(StationPins.visible(from: stations, in: wide, excluding: nil).isEmpty)
        // Just inside the threshold the same station is drawn, so the gate is what excluded it.
        let narrow = region(spanDegrees: StationPins.zoomThreshold - 0.01)
        #expect(StationPins.visible(from: stations, in: narrow, excluding: nil).map(\.id) == ["Cst"])
    }

    @Test("Only stations inside the padded region are drawn")
    func filtersToPaddedRegion() throws {
        let stations = try [
            station("Inside", latitudeOffset: 0.1),
            station("InPadding", latitudeOffset: 0.22),
            station("Outside", latitudeOffset: 0.3),
        ]
        let visible = StationPins.visible(from: stations, in: region(), excluding: nil)
        #expect(visible.map(\.id) == ["Inside", "InPadding"])
    }

    @Test("The selected station is skipped — it's drawn separately as a larger marker")
    func skipsSelectedStation() throws {
        let stations = try [station("Cst", latitudeOffset: 0), station("Sod", latitudeOffset: 0.05)]
        let visible = StationPins.visible(from: stations, in: region(), excluding: "Cst")
        #expect(visible.map(\.id) == ["Sod"])
    }

    @Test("Order follows the directory, so the drawn set is stable between refreshes")
    func preservesInputOrder() throws {
        let stations = try [station("B", latitudeOffset: 0.01), station("A", latitudeOffset: -0.01)]
        #expect(StationPins.visible(from: stations, in: region(), excluding: nil).map(\.id) == ["B", "A"])
    }
}
