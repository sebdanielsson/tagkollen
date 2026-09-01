import Foundation

/// Trafikverket emits several timestamp shapes:
/// - `2026-09-02T10:15:00.000+02:00` (local Swedish time with offset)
/// - `2026-09-02T08:15:00.123Z` (UTC, used for `ModifiedTime`)
/// - `2026-09-02T00:00:00` / `2026-09-02` (dates without zone — interpreted as Europe/Stockholm)
enum TRVDateParser {
    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let localDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let localDateTimeFraction: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    private static let localDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string)
            ?? withoutFraction.date(from: string)
            ?? localDateTimeFraction.date(from: string)
            ?? localDateTime.date(from: string)
            ?? localDate.date(from: string)
    }

    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised Trafikverket date format: \(raw)"
            )
        }
        return date
    }
}

public extension JSONDecoder {
    /// A decoder configured for Trafikverket API payloads.
    static var trafikverket: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = TRVDateParser.decodingStrategy
        return decoder
    }
}

/// Swedish civil time. The API reports advertised/estimated times in this zone.
public enum SwedishTime {
    public static let timeZone = TimeZone(identifier: "Europe/Stockholm")!

    public static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "sv_SE")
        return cal
    }

    /// `yyyy-MM-dd` in Swedish civil time — the format the API expects for date-valued filters.
    public static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// `yyyy-MM-dd'T'HH:mm:ss` in Swedish civil time — for datetime-valued filters.
    public static func dateTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }
}
