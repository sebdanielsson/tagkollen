import Foundation

/// A free-text message shown on platform signs and monitors at a station.
/// (Trafikverket's older `TrainMessage` object type is no longer served by the API.)
public struct TrainStationMessage: TRVObject, Hashable, Identifiable {
    public static let objectType = "TrainStationMessage"
    public static let namespace: String? = "rail.trafficinfo"
    public static let schemaVersion = "1"

    public var id: String
    /// `Plattformsskylt`, `Monitor`, …
    public var mediaType: String?
    /// Station signature the message is shown at.
    public var locationCode: String?
    public var startDateTime: Date?
    public var endDateTime: Date?
    public var freeText: String?
    public var status: String?
    public var versionNumber: Int64?
    public var deleted: Bool?
    public var modifiedTime: Date?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case mediaType = "MediaType"
        case locationCode = "LocationCode"
        case startDateTime = "StartDateTime"
        case endDateTime = "EndDateTime"
        case freeText = "FreeText"
        case status = "Status"
        case versionNumber = "VersionNumber"
        case deleted = "Deleted"
        case modifiedTime = "ModifiedTime"
    }

    /// Text with sign line breaks collapsed into spaces.
    public var displayText: String {
        (freeText ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isActive: Bool {
        let now = Date.now
        if let start = startDateTime, start > now {
            return false
        }
        if let end = endDateTime, end < now {
            return false
        }
        return !(deleted ?? false)
    }
}
