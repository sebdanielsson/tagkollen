# Contributing to Tågkollen

Thanks for taking the time to contribute. This document explains how to get set up and what we expect from changes.

## Getting started

1. Install Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. Register a free API key at [data.trafikverket.se](https://data.trafikverket.se) and put it in `.env.local` as `TRV_API_KEY=...`.
3. Run `Scripts/bootstrap.sh` to generate `Tagkollen.xcodeproj`, then open it.

The `.xcodeproj` is generated and git-ignored. Edit `project.yml` instead and re-run `xcodegen`.

## Development guidelines

- **Swift 6, strict concurrency.** Keep `@MainActor` on UI-facing observable classes and make everything else `Sendable`.
- **No third-party dependencies.** The app should build with only Apple frameworks. Open an issue before proposing one.
- **Only Trafikverket's open API** as a data source. Other APIs need a maintainer's OK first.
- **iOS 26 only.** Use the native Liquid Glass components (`glassEffect`, `.glass` button styles, adaptive tab bar) rather than custom chrome.
- **iPhone and iPad.** Check both a compact (iPhone) and a regular (iPad) layout before opening a pull request.
- **Localisation.** All user-facing strings go through SwiftUI's string catalog (`Localizable.xcstrings`). English is the source language; Swedish is a translation.
- **Formatting and linting.** Run `swiftformat .` and `swiftlint` before committing. CI checks both.
- **Tests.** `TrafikverketKit` is covered by `swift test`; app logic (journey assembly, formatting) lives in `TagkollenTests`. Add tests for new parsing or business logic.

## Pull requests

- Keep pull requests focused. One feature or fix per PR.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and PR titles (`feat: …`, `fix: …`, `docs: …`, `chore: …`). PRs are squash-merged and the title becomes the commit on `main`; release-please derives the next version and the changelog from it. See `docs/release.md`.
- Describe what changed and why, and add screenshots for UI changes (iPhone and iPad).
- Make sure `xcodebuild test` passes for the `Tagkollen` scheme.
- Follow the existing code style; the linters encode most of it.

## Reporting bugs

Open an issue with the app version, device or simulator, iOS version, and steps to reproduce. If the problem involves a specific train, include the train number and date so it can be looked up in the API.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind.
