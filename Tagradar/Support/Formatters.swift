import Foundation
import TrafikverketKit

/// Shared formatting helpers. All clock times are shown in Swedish civil time, because that is
/// what timetables and platform displays use regardless of where the user is.
enum Format {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = SwedishTime.timeZone
        f.locale = Locale.autoupdatingCurrent
        f.dateFormat = "HH:mm"
        return f
    }()

    static let timeWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = SwedishTime.timeZone
        f.locale = Locale.autoupdatingCurrent
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func clock(_ date: Date?) -> String {
        guard let date else { return "–" }
        return time.string(from: date)
    }

    static func day(_ date: Date, style: Date.FormatStyle.DateStyle = .abbreviated) -> String {
        var cal = Calendar.autoupdatingCurrent
        cal.timeZone = SwedishTime.timeZone
        if cal.isDateInToday(date) {
            return String(localized: "Today")
        }
        if cal.isDateInTomorrow(date) {
            return String(localized: "Tomorrow")
        }
        if cal.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// `+5 min`, `−2 min`, or `On time` for delays under a minute.
    static func delay(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let minutes = Int((seconds / 60).rounded())
        if minutes == 0 {
            return String(localized: "On time")
        }
        if minutes > 0 {
            return String(localized: "+\(minutes) min")
        }
        return String(localized: "−\(abs(minutes)) min")
    }

    static func relative(_ date: Date, to now: Date = .now) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    static func speed(_ kmh: Int?) -> String? {
        guard let kmh else { return nil }
        let measurement = Measurement(value: Double(kmh), unit: UnitSpeed.kilometersPerHour)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .general))
    }

    static func compass(_ bearing: Int?) -> String? {
        guard let bearing else { return nil }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(bearing).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return directions[(index + 8) % 8]
    }
}
