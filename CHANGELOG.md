# Changelog

Releases are cut by [release-please](https://github.com/googleapis/release-please) from [Conventional Commits](https://www.conventionalcommits.org/) on `main`; new sections are added above this one automatically. The project uses [Semantic Versioning](https://semver.org/).

## [0.1.1](https://github.com/sebdanielsson/tagkollen/compare/v0.1.0...v0.1.1) (2026-09-05)


### Bug Fixes

* **activity:** show minutes to the next stop instead of a seconds timer ([967ddbf](https://github.com/sebdanielsson/tagkollen/commit/967ddbfbd8d210da73b0fe3244cb78f36cb08750))
* **build:** stamp the widget extension with the app's build number ([b922e44](https://github.com/sebdanielsson/tagkollen/commit/b922e44f5592c6b73450c3ea57d8aace6f4587dd))
* keep the Live Activity updating in the background on cellular ([2a44052](https://github.com/sebdanielsson/tagkollen/commit/2a44052a0616cfcb7af58032de501ed35cc14da3))

## 0.1.0 (2026-09-05)

Initial development, before automated releases.

### Features

- Live map of all trains in Sweden with SSE updates and polling fallback.
- Train detail with all stops, planned/estimated/actual times, delays, deviations and traffic messages.
- Search by train number and date; station departure and arrival boards.
- Saved trains with live status, optionally limited to the stations where you board and get off.
- Local notifications for saved trains: delays, cancellations, track changes, arrival and a departure reminder, with a map attachment.
- Live Activities for followed trains (Lock Screen and Dynamic Island), refreshed in the background about once a minute via background URLSession wake-ups, with a self-running countdown, progress bar and upcoming stops.
- Home Screen and Lock Screen widgets: saved train and station departures.
- Background app refresh keeps notifications, Live Activities and widgets updated when iOS allows it.
- Icon Composer app icon in Trafikverket red with dark, clear and tinted appearances; original train glyph.
- Privacy policy, App Store submission checklist and screenshot script.
- iPhone and iPad layouts using iOS 26 Liquid Glass.
- `TrafikverketKit` Swift package with a typed request builder and models for the Trafikverket Open API.
