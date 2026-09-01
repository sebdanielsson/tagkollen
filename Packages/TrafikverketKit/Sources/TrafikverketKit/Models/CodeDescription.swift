import Foundation

/// A `Code` + `Description` pair used throughout TrainAnnouncement (deviations, product info, etc.).
public struct CodeDescription: Codable, Hashable, Sendable {
    public var code: String?
    public var description: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case description = "Description"
    }

    public init(code: String? = nil, description: String? = nil) {
        self.code = code
        self.description = description
    }
}

/// A location reference with display ordering, used for From/To/Via locations.
public struct LocationReference: Codable, Hashable, Sendable {
    /// Station signature (e.g. `Cst`), despite the field name.
    public var locationName: String
    public var priority: Int?
    public var order: Int?

    enum CodingKeys: String, CodingKey {
        case locationName = "LocationName"
        case priority = "Priority"
        case order = "Order"
    }

    public init(locationName: String, priority: Int? = nil, order: Int? = nil) {
        self.locationName = locationName
        self.priority = priority
        self.order = order
    }
}

/// Geometry in both SWEREF99TM and WGS84 WKT.
public struct Geometry: Codable, Hashable, Sendable {
    public var sweref99tm: String?
    public var wgs84: String?

    enum CodingKeys: String, CodingKey {
        case sweref99tm = "SWEREF99TM"
        case wgs84 = "WGS84"
    }

    public var coordinate: Coordinate? {
        wgs84.flatMap(Coordinate.init(wkt:))
    }
}
