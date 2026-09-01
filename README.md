# Tågkollen

Tågkollen is a native iOS and iPadOS app that shows every train in Sweden live on a map, lets you look up any train by number or station, and keeps track of upcoming trips. It is a modern, open-source alternative to Trafikverket's MinaTåg app, built entirely on Trafikverket's free open data.

> Tågkollen is an independent project and is not affiliated with or endorsed by Trafikverket.

## Features

- **Live map** of all trains with a GPS position, updated in real time over Server-Sent Events (falls back to polling). Markers show heading and are coloured by delay.
- **Train details**: every station on the run with planned, estimated and actual times, track, delay, deviations ("Spårändrat", "Buss ersätter", …), on-board services and the operator's link. A mini-map shows the live position, speed and heading.
- **Search** by train number on any date, or browse a station's departure and arrival board.
- **Saved trains**: pin an upcoming trip and see its status at a glance. Saved trains are stored on-device with SwiftData.
- **Traffic messages** from Trafikverket that affect the stations on your train's route.
- **iPhone and iPad** layouts. On iPad the tab bar adapts to a sidebar, lists get a split view, and the train detail opens as an inspector next to the full-size map.
- Built with SwiftUI, MapKit and the iOS 26 Liquid Glass design language. No third-party dependencies, no analytics, no tracking.

## Requirements

- iOS 26 / iPadOS 26 or later
- Xcode 26 to build
- A free Trafikverket API key (see below)

## Getting an API key

Trafikverket's open API is free but requires a personal key.

1. Create an account at [data.trafikverket.se](https://data.trafikverket.se).
2. Under *Mina sidor*, create an API key.
3. Either paste the key into the app on first launch (stored in the Keychain), or bake it into your own build as described under *Building*.

The data is published under [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

## Building

```bash
brew install xcodegen            # project file is generated, not committed
cp .env.example .env.local       # optional: put TRV_API_KEY=... here for a built-in dev key
Scripts/bootstrap.sh             # writes Config/Secrets.xcconfig and generates Tagkollen.xcodeproj
open Tagkollen.xcodeproj
```

Select the *Tagkollen* scheme and run on an iPhone or iPad simulator. Without a key in `.env.local` the app asks for one on first launch.

Command-line build and test:

```bash
xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
```

`Scripts/simulator.sh "iPhone 17 Pro"` builds, installs and launches the app on a named simulator (pass a second argument to save a screenshot).

The networking layer lives in the `TrafikverketKit` Swift package under `Packages/` and can be tested on its own with `swift test`.

## Project layout

```text
Tagkollen/                 SwiftUI app
  App/                     Entry point, dependency container, settings
  Models/                  TrainKey, TrainJourney, TrainStop, LiveTrain, FavoriteTrain (SwiftData)
  Services/                Live positions (SSE), station directory, delay index, timetable queries
  Views/                   Map, train detail, search, favorites, settings
Packages/TrafikverketKit/  Typed client for the Trafikverket Open API (request builder, models, SSE)
project.yml                XcodeGen spec
```

## Data sources

Everything comes from the [Trafikverket Open API](https://data.trafikverket.se):

| Object | Used for |
| --- | --- |
| `TrainPosition` | Live GPS positions, speed and bearing |
| `TrainAnnouncement` | Timetable, estimated and actual times, deviations |
| `TrainStation` | Station names and coordinates |
| `TrainMessage` | Traffic disruptions |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests are welcome in [Issues](https://github.com/sebdanielsson/tagkollen/issues).

## License

MIT — see [LICENSE](LICENSE).
