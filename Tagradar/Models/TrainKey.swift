import Foundation
import TrafikverketKit

/// Identifies one advertised train run: the ticket number plus its scheduled departure day.
struct TrainKey: Hashable, Codable, Sendable, Identifiable {
    /// `AdvertisedTrainIdent` — the number printed on the ticket.
    var ident: String
    /// Start of the scheduled departure day, Swedish civil time.
    var departureDate: Date

    init(ident: String, departureDate: Date) {
        self.ident = ident.trimmingCharacters(in: .whitespaces)
        self.departureDate = SwedishTime.calendar.startOfDay(for: departureDate)
    }

    /// `yyyy-MM-dd` for filters and storage.
    var dateString: String {
        SwedishTime.dateString(departureDate)
    }

    var id: String {
        "\(ident)@\(dateString)"
    }

    init?(id: String) {
        let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let date = TRVDateParserBridge.date(fromDay: parts[1]) else { return nil }
        self.init(ident: parts[0], departureDate: date)
    }

    static func today(_ ident: String) -> TrainKey {
        TrainKey(ident: ident, departureDate: .now)
    }
}

/// Small bridge so the app can parse `yyyy-MM-dd` the same way the kit does.
enum TRVDateParserBridge {
    static func date(fromDay day: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = SwedishTime.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }
}
