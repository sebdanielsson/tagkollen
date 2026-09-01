# Trafikverket Open API notes

Reference for how Tågkollen talks to the [Trafikverket Open API](https://data.trafikverket.se). Everything goes through `TrafikverketKit`.

## Endpoint and request shape

- `POST https://api.trafikinfo.trafikverket.se/v2/data.json` with `Content-Type: text/xml`.
- Body is an XML `<REQUEST>` with one `<LOGIN authenticationkey="…"/>` and one or more `<QUERY>` elements.
- `<QUERY>` attributes used: `objecttype`, `namespace`, `schemaversion`, `limit`, `orderby`, `changeid`, `sseurl`.
- Filters live in `<FILTER>` (`EQ`, `GT`, `GTE`, `LT`, `LIKE`, `IN`, `EXISTS`, `AND`, `OR`, `NOT`, …). Dates accept `$now` and `$dateadd(days.hh:mm:ss)`, e.g. `$dateadd(-0.00:15:00)`.
- `<INCLUDE>` limits returned fields; keep payloads small.
- Responses: `{"RESPONSE":{"RESULT":[{"<ObjectType>":[…],"INFO":{"LASTCHANGEID":"…","SSEURL":"…"}}]}}`. Errors: `{"RESPONSE":{"RESULT":[{"ERROR":{"SOURCE":"Security","MESSAGE":"Invalid authentication"}}]}}` (HTTP 401 for bad keys).

## Object types

| Object | Namespace | Version | Used for |
| --- | --- | --- | --- |
| `TrainPosition` | `rail.trafficinfo` | 1.1 | Live GPS, speed, bearing. `Position.WGS84` is WKT `POINT (lon lat)`. |
| `TrainAnnouncement` | `rail.trafficinfo` | 2.0 | One row per arrival/departure per station. `Deviation`, `ProductInformation`, `OtherInformation`, `Service`, `Booking`, `TrainComposition`, `TypeOfTraffic` are `{Code, Description}` arrays. |
| `TrainStation` | `rail.infrastructure` | 1.5 | Station names and coordinates; cached on device for a week. |
| `TrainMessage` | `rail.trafficinfo` | 1.7 | Traffic disruptions with affected stations. |
| `ReasonCode` | `rail.trafficinfo` | 1 | Lookup for deviation codes (not currently fetched). |

## Key concepts

- **Advertised train number** (`AdvertisedTrainIdent` / `TrainPosition.Train.AdvertisedTrainNumber`) is the number on the ticket. Combined with the scheduled departure day (`ScheduledDepartureDateTime`, `OperationalTrainDepartureDate`) it identifies a run — see `TrainKey`.
- **Operational train number** (`OperationalTrainNumber`) is Trafikverket's internal id; freight trains only have this.
- **Times**: `AdvertisedTimeAtLocation` (timetable), `EstimatedTimeAtLocation` (forecast), `TimeAtLocation` (actual). Delay is actual/estimated minus advertised. `EstimatedTimeIsPreliminary` marks uncertain forecasts.
- **Cancellation**: `Canceled` per announcement. A run is fully canceled when every stop is canceled.
- Times are in Swedish civil time with offset; `ModifiedTime` is UTC.

## Live updates

Adding `sseurl="true"` to a query returns `INFO.SSEURL`. Connecting to it yields Server-Sent Events whose `data:` payload has the same shape as a normal response and contains only changed objects. Tågkollen streams `TrainPosition` this way and falls back to polling the snapshot query every 15 s if the stream fails.

## Queries the app makes

- **Map**: `TrainPosition` where `TimeStamp > $dateadd(-0.00:15:00)`, streamed.
- **Marker colours**: `TrainAnnouncement` for the visible trains (`IN AdvertisedTrainIdent`, today, `AdvertisedTimeAtLocation > $dateadd(-0.01:30:00)`), refreshed every 45 s.
- **Train detail**: all `TrainAnnouncement` rows for `AdvertisedTrainIdent` on the day, ordered by `AdvertisedTimeAtLocation`, plus active `TrainMessage`s touching its stations.
- **Station board**: `TrainAnnouncement` with `ActivityType = Avgang|Ankomst`, `LocationSignature`, six-hour window.
- **Stations**: `TrainStation` where `Advertised = true`, cached.

## Licence

Data is CC0. Trafikverket asks integrators to register for a personal key and not to share it.
