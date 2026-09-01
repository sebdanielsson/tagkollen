# Tågkollen — repo notes for AI assistants

- Native SwiftUI app, iOS 26+, Swift 6 strict concurrency. No third-party packages. Only Trafikverket's Open API as data source.
- The Xcode project is generated: edit `project.yml`, then run `xcodegen` (or `Scripts/bootstrap.sh`). Never commit `Tagkollen.xcodeproj`.
- API key: `.env.local` → `Scripts/bootstrap.sh` → `Config/Secrets.xcconfig` → `Info.plist` key `TRVAPIKey`. Users can override in Settings (Keychain). Never commit keys.
- `Packages/TrafikverketKit` is platform-agnostic and testable with `swift test`. App-level logic tests live in `TagkollenTests`.
- User-facing strings are English source keys in `Tagkollen/Resources/Localizable.xcstrings` with Swedish translations. Code, comments and commits are in English.
- Build: `xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
