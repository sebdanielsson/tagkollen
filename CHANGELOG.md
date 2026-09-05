# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Live map of all trains in Sweden with SSE updates and polling fallback.
- Train detail with all stops, planned/estimated/actual times, delays, deviations and traffic messages.
- Search by train number and date; station departure and arrival boards.
- Saved trains with live status, optionally limited to the stations where you board and get off.
- Local notifications for saved trains: delays, cancellations, track changes, arrival and a departure reminder, with a map attachment.
- Live Activities for followed trains (Lock Screen and Dynamic Island).
- Home Screen and Lock Screen widgets: saved train and station departures.
- Background app refresh keeps notifications, Live Activities and widgets updated when iOS allows it.
- iPhone and iPad layouts using iOS 26 Liquid Glass.
- `TrafikverketKit` Swift package with a typed request builder and models for the Trafikverket Open API.
