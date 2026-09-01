import Foundation

/// Lookup table for deviation / reason codes.
public struct ReasonCode: TRVObject, Hashable, Identifiable {
    public static let objectType = "ReasonCode"
    public static let namespace: String? = "rail.trafficinfo"
    public static let schemaVersion = "1"

    public var code: String
    public var groupDescription: String?
    public var level1Description: String?
    public var level2Description: String?
    public var level3Description: String?
    public var deleted: Bool?
    public var modifiedTime: Date?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case groupDescription = "GroupDescription"
        case level1Description = "Level1Description"
        case level2Description = "Level2Description"
        case level3Description = "Level3Description"
        case deleted = "Deleted"
        case modifiedTime = "ModifiedTime"
    }

    public var id: String {
        code
    }
}
