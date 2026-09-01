import Foundation
import TrafikverketKit

/// Timetable queries: whole journeys, station departure boards and traffic messages.
struct TrainService: Sendable {
    let client: TrafikverketClient

    /// Loads every advertised arrival/departure for a train run and assembles the journey.
    func journey(for key: TrainKey) async throws -> TrainJourney? {
        let rows = try await announcements(ident: key.ident, day: key.dateString)
        guard !rows.isEmpty else { return nil }
        return TrainJourney(key: key, announcements: rows)
    }

    /// Finds journeys by train number on a given day. Usually one result, occasionally more
    /// when the same number is reused by different operators.
    func search(ident: String, on date: Date) async throws -> [TrainJourney] {
        let trimmed = ident.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let day = SwedishTime.dateString(date)
        let rows = try await announcements(ident: trimmed, day: day)
        guard !rows.isEmpty else { return [] }
        // Split by operational train number in case two distinct runs share the advertised number.
        let groups = Dictionary(grouping: rows) { $0.operationalTrainNumber ?? "" }
        let key = TrainKey(ident: trimmed, departureDate: date)
        if groups.count <= 1 {
            return [TrainJourney(key: key, announcements: rows)]
        }
        return groups.values.map { TrainJourney(key: key, announcements: $0) }
            .sorted { ($0.scheduledDeparture ?? .distantFuture) < ($1.scheduledDeparture ?? .distantFuture) }
    }

    private func announcements(ident: String, day: String) async throws -> [TrainAnnouncement] {
        let query = Query<TrainAnnouncement>()
            .filter(
                .equal("AdvertisedTrainIdent", ident),
                .greaterThanOrEqual("ScheduledDepartureDateTime", "\(day)T00:00:00"),
                .lessThan("ScheduledDepartureDateTime", "\(day)T23:59:59")
            )
            .include(TrainAnnouncement.appFields)
            .orderBy(Sort("AdvertisedTimeAtLocation"))
            .limit(1000)
        let result = try await client.fetch(query)
        return result.objects
            .filter { !($0.deleted ?? false) && ($0.advertised ?? true) }
    }

    /// Departures from a station in a time window.
    func departures(from signature: String, start: Date, hours: Int = 6, limit: Int = 200) async throws -> [TrainAnnouncement] {
        let end = start.addingTimeInterval(TimeInterval(hours) * 3600)
        let query = Query<TrainAnnouncement>()
            .filter(
                .equal("ActivityType", "Avgang"),
                .equal("LocationSignature", signature),
                .equal("Advertised", true),
                .greaterThanOrEqual("AdvertisedTimeAtLocation", date: start),
                .lessThan("AdvertisedTimeAtLocation", date: end)
            )
            .include(TrainAnnouncement.appFields)
            .orderBy(Sort("AdvertisedTimeAtLocation"))
            .limit(limit)
        return try await client.fetch(query).objects.filter { !($0.deleted ?? false) }
    }

    /// Arrivals to a station in a time window.
    func arrivals(to signature: String, start: Date, hours: Int = 6, limit: Int = 200) async throws -> [TrainAnnouncement] {
        let end = start.addingTimeInterval(TimeInterval(hours) * 3600)
        let query = Query<TrainAnnouncement>()
            .filter(
                .equal("ActivityType", "Ankomst"),
                .equal("LocationSignature", signature),
                .equal("Advertised", true),
                .greaterThanOrEqual("AdvertisedTimeAtLocation", date: start),
                .lessThan("AdvertisedTimeAtLocation", date: end)
            )
            .include(TrainAnnouncement.appFields)
            .orderBy(Sort("AdvertisedTimeAtLocation"))
            .limit(limit)
        return try await client.fetch(query).objects.filter { !($0.deleted ?? false) }
    }

    /// Current traffic messages, optionally narrowed to those touching the given stations.
    func messages(affecting signatures: Set<String>? = nil) async throws -> [TrainMessage] {
        let query = Query<TrainMessage>()
            .filter(
                .or([
                    .exists("EndDateTime", false),
                    .greaterThan("EndDateTime", "$now"),
                ]),
                .lessThanOrEqual("StartDateTime", "$dateadd(0.06:00:00)")
            )
            .orderBy(Sort("StartDateTime", .descending))
            .limit(300)
        let all = try await client.fetch(query).objects.filter { !($0.deleted ?? false) }
        guard let signatures else { return all }
        return all.filter { !$0.affectedSignatures.isDisjoint(with: signatures) }
    }
}
