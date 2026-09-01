# Security Policy

## Supported versions

Only the latest release on the `main` branch is supported.

## Reporting a vulnerability

Please do not open public issues for security problems. Use GitHub's private vulnerability reporting on this repository ("Security" tab → "Report a vulnerability"). You should get a response within a week.

## Scope notes

- Tågkollen stores the user's Trafikverket API key in the iOS Keychain and never transmits it anywhere other than `api.trafikinfo.trafikverket.se`.
- The app collects no analytics and has no backend of its own.
