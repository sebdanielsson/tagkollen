import CoreLocation
import Foundation
@testable import Tagradar
import Testing
import TrafikverketKit

/// `StationDirectory.nearest` decides which station the "Near you" sheet section shows —
/// pinning the distance cap.
@Suite("Station directory: nearest")
struct StationDirectoryTests {
    private static let centre = CLLocation(latitude: 59.33, longitude: 18.06)

    private func station(_ signature: String, latitudeOffset: CLLocationDegrees = 0) throws -> LocatedStation {
        let json = Data(#"{"LocationSignature":"\#(signature)"}"#.utf8)
        let decoded = try JSONDecoder.trafikverket.decode(TrainStation.self, from: json)
        return LocatedStation(
            station: decoded,
            coordinate: Coordinate(
                latitude: Self.centre.coordinate.latitude + latitudeOffset,
                longitude: Self.centre.coordinate.longitude
            )
        )
    }

    @Test("Picks the closest station")
    func picksTheClosest() throws {
        let stations = try [station("Far", latitudeOffset: 0.2), station("Near", latitudeOffset: 0.01)]
        #expect(StationDirectory.nearest(among: stations, to: Self.centre)?.locationSignature == "Near")
    }

    @Test("Beyond the distance cap, there is no nearest station")
    func nilBeyondTheCap() throws {
        // 2° of latitude is about 222 km, far outside the default 40 km cap.
        let stations = try [station("TooFar", latitudeOffset: 2)]
        #expect(StationDirectory.nearest(among: stations, to: Self.centre) == nil)
    }

    /// Without this the cap could be ignored altogether and every other test would still pass.
    @Test("The distance cap is the caller's to set")
    func honoursAnExplicitCap() throws {
        // 0.2° of latitude is about 22 km: inside the 40 km default, outside a 10 km cap.
        let stations = try [station("Nearby", latitudeOffset: 0.2)]
        #expect(StationDirectory.nearest(among: stations, to: Self.centre)?.locationSignature == "Nearby")
        #expect(StationDirectory.nearest(among: stations, to: Self.centre, maxDistance: 10000) == nil)
    }

    @Test("An empty directory has no nearest station")
    func nilForEmptyDirectory() {
        #expect(StationDirectory.nearest(among: [], to: Self.centre) == nil)
    }
}
