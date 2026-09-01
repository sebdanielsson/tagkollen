import Foundation

/// Live GPS position for a train. Updated roughly every few seconds per train.
public struct TrainPosition: TRVObject, Hashable, Identifiable {
    public static let objectType = "TrainPosition"
    public static let namespace: String? = "rail.trafficinfo"
    public static let schemaVersion = "1.1"

    public struct Train: Codable, Hashable, Sendable {
        public var operationalTrainNumber: String?
        public var operationalTrainDepartureDate: Date?
        public var journeyPlanNumber: String?
        public var journeyPlanDepartureDate: Date?
        /// The number printed on the ticket. Matches `TrainAnnouncement.advertisedTrainIdent`.
        public var advertisedTrainNumber: String?

        enum CodingKeys: String, CodingKey {
            case operationalTrainNumber = "OperationalTrainNumber"
            case operationalTrainDepartureDate = "OperationalTrainDepartureDate"
            case journeyPlanNumber = "JourneyPlanNumber"
            case journeyPlanDepartureDate = "JourneyPlanDepartureDate"
            case advertisedTrainNumber = "AdvertisedTrainNumber"
        }
    }

    public struct Status: Codable, Hashable, Sendable {
        public var active: Bool?
        enum CodingKeys: String, CodingKey { case active = "Active" }
    }

    public var train: Train?
    public var position: Geometry?
    public var timeStamp: Date?
    public var status: Status?
    /// Bearing in degrees, 0 = north.
    public var bearing: Int?
    /// Speed in km/h.
    public var speed: Int?
    public var versionNumber: Int64?
    public var modifiedTime: Date?
    public var deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case train = "Train"
        case position = "Position"
        case timeStamp = "TimeStamp"
        case status = "Status"
        case bearing = "Bearing"
        case speed = "Speed"
        case versionNumber = "VersionNumber"
        case modifiedTime = "ModifiedTime"
        case deleted = "Deleted"
    }

    /// Stable identity across updates: operational train number + departure day.
    public var id: String {
        let number = train?.operationalTrainNumber ?? train?.advertisedTrainNumber ?? "?"
        let day = train?.operationalTrainDepartureDate.map(SwedishTime.dateString) ?? ""
        return "\(number)@\(day)"
    }

    public var coordinate: Coordinate? {
        position?.coordinate
    }

    public var isActive: Bool {
        status?.active ?? true
    }
}
