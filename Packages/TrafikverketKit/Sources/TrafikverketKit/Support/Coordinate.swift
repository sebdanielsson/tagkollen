import Foundation

/// A WGS84 coordinate parsed from Trafikverket's `POINT (lon lat)` well-known-text format.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Parses `POINT (17.63 59.85)` (longitude first, as in WKT). Returns nil for malformed input.
    public init?(wkt: String) {
        guard let open = wkt.firstIndex(of: "("), let close = wkt.lastIndex(of: ")"), open < close else {
            return nil
        }
        let inner = wkt[wkt.index(after: open) ..< close]
        let parts = inner.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let lon = parts[0], lat = parts[1]
        guard (-90 ... 90).contains(lat), (-180 ... 180).contains(lon) else { return nil }
        self.init(latitude: lat, longitude: lon)
    }

    /// Well-known-text representation understood by the API's spatial filters.
    public var wkt: String {
        "POINT (\(longitude) \(latitude))"
    }
}
