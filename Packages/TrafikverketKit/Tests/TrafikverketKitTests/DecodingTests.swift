import Foundation
import Testing
@testable import TrafikverketKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try Data(contentsOf: url)
}

@Suite("Response decoding")
struct DecodingTests {
    @Test func decodesTrainPositions() throws {
        let result = try ResponseEnvelope.decode(fixture("trainposition"), as: TrainPosition.self)
        #expect(result.objects.count == 2)
        #expect(result.info.lastChangeID == "7130947329371865088")
        #expect(result.info.sseURL?.host() == "api.trafikinfo.trafikverket.se")

        let first = result.objects[0]
        #expect(first.train?.advertisedTrainNumber == "520")
        #expect(first.speed == 92)
        #expect(first.bearing == 187)
        #expect(first.isActive)
        let coord = try #require(first.coordinate)
        #expect(abs(coord.latitude - 59.33033) < 0.00001)
        #expect(abs(coord.longitude - 18.05789) < 0.00001)
        #expect(first.id == "10520@2026-09-02")
        #expect(!result.objects[1].isActive)
    }

    @Test func decodesTrainAnnouncements() throws {
        let result = try ResponseEnvelope.decode(fixture("trainannouncement"), as: TrainAnnouncement.self)
        #expect(result.objects.count == 3)
        let departure = result.objects[0]
        #expect(departure.activityType == .departure)
        #expect(departure.productInformation?.first?.description == "SJ Snabbtåg")
        #expect(departure.toLocation?.first?.locationName == "G")
        #expect(departure.delay == 8 * 60.0)
        #expect(!departure.hasDeparted)

        let arrival = result.objects[1]
        #expect(arrival.activityType == .arrival)
        #expect(arrival.hasDeparted)
        #expect(arrival.delay == 3 * 60.0)
        #expect(arrival.deviation?.first?.description == "Spårändrat")

        #expect(result.objects[2].isCanceled)
    }

    @Test func decodesStations() throws {
        let result = try ResponseEnvelope.decode(fixture("trainstation"), as: TrainStation.self)
        #expect(result.objects.map(\.id) == ["Cst", "U"])
        #expect(result.objects[0].name == "Stockholm Central")
        #expect(result.objects[0].platformLine == ["1", "2", "3"])
        #expect(result.objects[1].coordinate != nil)
    }

    @Test func surfacesAuthenticationErrors() throws {
        #expect(throws: TrafikverketError.invalidAuthentication) {
            _ = try ResponseEnvelope.decode(fixture("error"), as: TrainStation.self)
        }
    }

    @Test func parsesDateVariants() {
        #expect(TRVDateParser.parse("2026-09-02T06:21:00.000+02:00") != nil)
        #expect(TRVDateParser.parse("2026-09-01T23:10:13.421Z") != nil)
        #expect(TRVDateParser.parse("2026-09-01T23:10:13Z") != nil)
        #expect(TRVDateParser.parse("2026-09-02T00:00:00") != nil)
        #expect(TRVDateParser.parse("2026-09-02") != nil)
        #expect(TRVDateParser.parse("nonsense") == nil)
    }

    @Test func parsesWKTPoints() {
        #expect(Coordinate(wkt: "POINT (18.05789 59.33033)")?.latitude == 59.33033)
        #expect(Coordinate(wkt: "POINT(18.05789 59.33033)")?.longitude == 18.05789)
        #expect(Coordinate(wkt: "LINESTRING (1 2, 3 4)")?.latitude == 2) // takes the first pair
        #expect(Coordinate(wkt: "POINT ()") == nil)
        #expect(Coordinate(wkt: "POINT (200 95)") == nil)
    }

    @Test func splitsSSELines() {
        #expect(SSEConnection.split("data: {\"a\":1}") == ("data", "{\"a\":1}"))
        #expect(SSEConnection.split("event:update") == ("event", "update"))
        #expect(SSEConnection.split("nocolon") == ("nocolon", ""))
    }
}
