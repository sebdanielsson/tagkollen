# Releasing Tågkollen

How builds get to TestFlight and the App Store, and what a maintainer has to set up once. The pipeline is `.github/workflows/ci.yml`; nothing is built or signed on anyone's Mac.

## The flow

```text
push / PR ──▶ verify (lint, format, tests, simulator build)
                 │
   push to main ─┼──▶ testflight     archive → upload to TestFlight (build = run number)
                 │
                 └──▶ release-please  keeps a "chore(main): release X.Y.Z" PR up to date
                          │
      merge that PR ──────┴──▶ tag vX.Y.Z + GitHub release
                                  └──▶ appstore  archive → upload → metadata + screenshots → submit for review
```

- **Every push to `main`** produces a TestFlight build. Internal testers see it after Apple's processing; the build number is the workflow run number, the version is `version.txt`.
- **Releases** are driven by [release-please](https://github.com/googleapis/release-please). It reads the commit messages on `main` and maintains a release pull request that bumps `version.txt`, `project.yml` (`MARKETING_VERSION`) and `CHANGELOG.md`. Merging that PR creates the tag and the GitHub release, and the same workflow run then submits the tagged build to App Store Review.
- After Apple approves, **release it manually** in App Store Connect (the workflow sets `automatic_release: false`), so the store listing and the GitHub release can go out together.

### Commit messages decide the version

release-please uses [Conventional Commits](https://www.conventionalcommits.org/):

| Commit | Effect |
|---|---|
| `fix: ...` | patch bump, listed under Bug Fixes |
| `feat: ...` | minor bump, listed under Features |
| `feat!: ...` or a `BREAKING CHANGE:` footer | major bump (minor while still on 0.x) |
| `docs:`, `chore:`, `ci:`, `refactor:`, `test:`, `build:` | no release on their own, hidden from the changelog |

Squash-merge pull requests and make the PR title a conventional commit; that title becomes the commit on `main`. To pick an exact version (for example the first `1.0.0`), add a footer `Release-As: 1.0.0` to any commit on `main`, or edit the version in the release PR.

## One-time setup

### 1. Apple Developer / App Store Connect

- Paid Apple Developer Program membership. Bundle identifier `se.tagkollen.app` (plus `.widgets`) is registered by Xcode's automatic signing on the first archive, together with App Groups (`group.se.tagkollen.app`), Keychain Sharing and Background Modes.
- In App Store Connect, create the app once: name **Tågkollen**, bundle ID `se.tagkollen.app`, SKU e.g. `tagkollen`, primary language English, availability Sweden (and anywhere else). The workflow fills in metadata, screenshots and the What's New text; **age rating** (4+) and the **App Privacy** questionnaire ("no data collected", see `PRIVACY.md`) must be answered by hand in App Store Connect the first time.
- **API key**: App Store Connect → Users and Access → Integrations → App Store Connect API → *Team Keys* → Generate. Role **Admin** (cloud-managed signing needs Admin; App Manager is enough for uploads but not for creating the distribution certificate). Download the `.p8` once; note the Key ID and the Issuer ID.
- TestFlight: add internal testers under the app's TestFlight tab. Every upload becomes available to them automatically.

### 2. GitHub secrets

Repository → Settings → Secrets and variables → Actions → *Repository secrets*:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-character team ID (also hard-coded as `teamID` in `ExportOptions*.plist`) |
| `APP_STORE_CONNECT_KEY_ID` | Key ID of the API key |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID shown above the key list |
| `APP_STORE_CONNECT_KEY_BASE64` | The `.p8` file, base64 encoded: `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy`. Pasting the raw PEM works too. |
| `TRV_API_KEY` | Trafikverket Open API key baked into the build |

`Scripts/ci/write-asc-key.sh` checks that the decoded key is a PEM file before Xcode uses it. "Authentication failed: Make sure a bearer token was provided" from `xcodebuild` means the key, key ID and issuer ID do not belong together, the key was revoked, or it is an *individual* key instead of a *team* key.

### 3. GitHub settings

- Settings → Actions → General → *Workflow permissions*: tick **Allow GitHub Actions to create and approve pull requests** (release-please opens the release PR with the built-in token).
- Environments `testflight` and `app-store` are created automatically on first use. Optionally add yourself as a **required reviewer** on `app-store` to get an approval step before anything is submitted to Apple.

## Day to day

- Merge work into `main` with conventional commit messages → TestFlight build appears, release PR is updated.
- When ready to ship: merge the release PR → wait for the *App Store* job → approve/release in App Store Connect.
- On-demand TestFlight from any branch: Actions → CI/CD → *Run workflow*.
- Store text lives in `fastlane/metadata/<locale>/*.txt` (English `en-US`, Swedish `sv`); screenshots in `fastlane/screenshots/<locale>/` (`Scripts/screenshots.sh` regenerates them at the sizes App Store Connect requires; `LOCALE=sv` for Swedish). Both are uploaded with every release and overwrite what is in App Store Connect.
- App Privacy details cannot be updated through the API key; change them in App Store Connect if the app ever starts collecting data.

## Signing certificates

The archive is signed for development and every runner starts with an empty keychain, so `-allowProvisioningUpdates` mints a fresh **Apple Development** certificate on every TestFlight and App Store run. Apple caps how many certificates an account may hold; once the cap is reached the archive step fails with:

```text
Choose a certificate to revoke. Your account has reached the maximum number of certificates.
No profiles for 'se.tagkollen.app' were found: Xcode couldn't find any iOS App Development provisioning profiles…
```

The second line is a consequence of the first — no certificate, no profile. Removing builds in App Store Connect changes nothing; certificates live in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).

`Scripts/ci/revoke-build-certificate.rb` runs at the end of both signing jobs and hands that certificate back through the App Store Connect API, so CI leaves nothing behind. It only revokes certificates that are in that runner's own keychain, matched on the certificate itself rather than on a name, so a certificate someone develops with is never touched. It never fails the job: if the API call breaks it prints a `::warning::` and the list has to be cleared by hand. Revoking an Apple Development certificate is safe — builds already on TestFlight or the App Store are distribution signed, and Xcode recreates a local one on demand.

The distribution certificate is cloud managed, meaning Apple keeps the private key and hands it back on every run, so it is created once and never counts against this.

## Building to your own device from another team

Bundle IDs and App Groups are unique across Apple teams, so a developer who is not on the release team cannot sign `se.tagkollen.app`. Put your own prefix in `.env.local` and run `Scripts/bootstrap.sh`:

```bash
APP_BUNDLE_ID=se.example.tagkollen
DEVELOPMENT_TEAM=XXXXXXXXXX
```

Everything derived from it (widget bundle ID, App Group, Keychain group, background task identifier) follows. CI and release builds do not set `APP_BUNDLE_ID` and therefore use `se.tagkollen.app`.

## Local equivalents

```bash
Scripts/bootstrap.sh                 # Secrets.xcconfig + Xcode project
Scripts/screenshots.sh               # App Store screenshots
fastlane release ipa:… version:…     # what the appstore job runs (needs the same env vars)
```
