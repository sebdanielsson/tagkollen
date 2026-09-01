import Foundation

/// A traffic message (disruption / event) published by Trafikverket.
public struct TrainMessage: TRVObject, Hashable, Identifiable {
    public static let objectType = "TrainMessage"
    public static let namespace: String? = "rail.trafficinfo"
    public static let schemaVersion = "1.7"

    public struct TrafficImpact: Codable, Hashable, Sendable {
        public struct AffectedLocation: Codable, Hashable, Sendable {
            public var locationSignature: String?
            public var shouldBeTrafficInformed: Bool?
            enum CodingKeys: String, CodingKey {
                case locationSignature = "LocationSignature"
                case shouldBeTrafficInformed = "ShouldBeTrafficInformed"
            }
        }

        public var isConfirmed: Bool?
        public var fromLocation: [String]?
        public var affectedLocation: [AffectedLocation]?
        public var toLocation: [String]?

        enum CodingKeys: String, CodingKey {
            case isConfirmed = "IsConfirmed"
            case fromLocation = "FromLocation"
            case affectedLocation = "AffectedLocation"
            case toLocation = "ToLocation"
        }
    }

    public var countyNo: [Int]?
    public var deleted: Bool?
    public var externalDescription: String?
    public var geometry: Geometry?
    public var eventId: String
    public var header: String?
    public var reasonCode: [CodeDescription]?
    public var trafficImpact: [TrafficImpact]?
    public var startDateTime: Date?
    public var prognosticatedEndDateTimeTrafficImpact: Date?
    public var endDateTime: Date?
    public var lastUpdateDateTime: Date?
    public var modifiedTime: Date?

    enum CodingKeys: String, CodingKey {
        case countyNo = "CountyNo"
        case deleted = "Deleted"
        case externalDescription = "ExternalDescription"
        case geometry = "Geometry"
        case eventId = "EventId"
        case header = "Header"
        case reasonCode = "ReasonCode"
        case trafficImpact = "TrafficImpact"
        case startDateTime = "StartDateTime"
        case prognosticatedEndDateTimeTrafficImpact = "PrognosticatedEndDateTimeTrafficImpact"
        case endDateTime = "EndDateTime"
        case lastUpdateDateTime = "LastUpdateDateTime"
        case modifiedTime = "ModifiedTime"
    }

    public var id: String {
        eventId
    }

    /// All station signatures this message touches.
    public var affectedSignatures: Set<String> {
        var set = Set<String>()
        for impact in trafficImpact ?? [] {
            for loc in impact.affectedLocation ?? [] {
                if let sig = loc.locationSignature {
                    set.insert(sig)
                }
            }
            for sig in impact.fromLocation ?? [] {
                set.insert(sig)
            }
            for sig in impact.toLocation ?? [] {
                set.insert(sig)
            }
        }
        return set
    }
}
