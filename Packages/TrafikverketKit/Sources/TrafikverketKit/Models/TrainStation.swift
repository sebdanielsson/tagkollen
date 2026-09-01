import Foundation

/// A station or other announced location on the Swedish rail network.
public struct TrainStation: TRVObject, Codable, Hashable, Identifiable {
    public static let objectType = "TrainStation"
    public static let namespace: String? = "rail.infrastructure"
    public static let schemaVersion = "1.5"

    public var advertised: Bool?
    public var advertisedLocationName: String?
    public var advertisedShortLocationName: String?
    public var countryCode: String?
    public var countyNo: [Int]?
    public var deleted: Bool?
    public var geometry: Geometry?
    public var locationInformationText: String?
    public var locationSignature: String
    public var platformLine: [String]?
    public var prognosticated: Bool?
    public var officialLocationName: String?
    public var modifiedTime: Date?

    enum CodingKeys: String, CodingKey {
        case advertised = "Advertised"
        case advertisedLocationName = "AdvertisedLocationName"
        case advertisedShortLocationName = "AdvertisedShortLocationName"
        case countryCode = "CountryCode"
        case countyNo = "CountyNo"
        case deleted = "Deleted"
        case geometry = "Geometry"
        case locationInformationText = "LocationInformationText"
        case locationSignature = "LocationSignature"
        case platformLine = "PlatformLine"
        case prognosticated = "Prognosticated"
        case officialLocationName = "OfficialLocationName"
        case modifiedTime = "ModifiedTime"
    }

    public var id: String {
        locationSignature
    }

    /// Display name with sensible fallbacks.
    public var name: String {
        advertisedLocationName ?? officialLocationName ?? advertisedShortLocationName ?? locationSignature
    }

    public var coordinate: Coordinate? {
        geometry?.coordinate
    }

    public static let appFields: [String] = [
        "Advertised", "AdvertisedLocationName", "AdvertisedShortLocationName", "CountryCode", "CountyNo",
        "Deleted", "Geometry.WGS84", "LocationInformationText", "LocationSignature", "OfficialLocationName",
        "PlatformLine", "Prognosticated", "ModifiedTime",
    ]
}
