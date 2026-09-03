# App Store submission checklist

What Tågkollen needs before it can be submitted, what is already in the repository, and what has to be done by hand in App Store Connect. Sources: Apple's [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/) and [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) references, the [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) Human Interface Guidelines and [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Account

- [ ] Paid Apple Developer Program membership. The free Personal Team can build to your own devices but cannot upload to App Store Connect, and it cannot use push notifications. Everything else the app does (App Groups, Live Activities, local notifications, background refresh) works on both.
- [ ] Bundle ID `se.tagkollen.app` registered with capabilities: App Groups (`group.se.tagkollen.app`), Keychain Sharing, Background Modes. Xcode's automatic signing does this on first archive.
- [ ] `DEVELOPMENT_TEAM` in `.env.local` set to the paid team.

## App icon (done)

- `Tagkollen/AppIcon.icon` is an Icon Composer package. Xcode compiles every size and the six iOS 26 appearances (default, dark, clear light, clear dark, tinted light, tinted dark) from it, plus the 1024 × 1024 App Store icon. Nothing else is needed in App Store Connect.
- Colours: default background Trafikverket red `#D70000` (RGB 215 0 0, the main red in Trafikverket's graphic manual), dark appearance `#AF0000`. Clear and tinted variants are derived by the system from the white layers.
- The glyph is original artwork drawn in `Scripts/make-app-icon.swift`. Apple's SF Symbols licence forbids using SF Symbols, or glyphs confusingly similar to them, in app icons.
- Regenerate layers with `swift Scripts/make-app-icon.swift`; preview every appearance with Icon Composer (Xcode > Open Developer Tool) or:

  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
    Tagkollen/AppIcon.icon --export-image --output-file out.png --platform iOS --rendition Dark \
    --width 1024 --height 1024 --scale 1
  ```

  Renditions: `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight`, `TintedDark` (tinted ones take `--tint-color 0.6 --tint-strength 0.75`).
- `Marketing/AppIcon-1024.png` is a flattened fallback (no alpha) if App Store Connect ever asks for a file.

## Screenshots

App Store Connect requires at least one set per device family the app runs on. Alpha channels are not allowed, 1–10 images per size.

| Family | Required size | Pixels (portrait) | Simulator |
|---|---|---|---|
| iPhone 6.9" | required | 1320 × 2868 | iPhone 17 Pro Max |
| iPad 13" | required (app runs on iPad) | 2064 × 2752 | iPad Pro 13-inch (M5) |

`Scripts/screenshots.sh` boots both simulators, sets a 9:41 status bar and captures the map and a train detail into `Marketing/Screenshots/`. Add more captures there (station board, saved trains, widgets) as the app evolves. Both English and Swedish screenshots are worth uploading; run with the simulator language switched (`xcrun simctl spawn <udid> defaults write .GlobalPreferences AppleLanguages -array sv`).

## Version and build

- `CFBundleShortVersionString` is `0.1.0` in `project.yml`; set it to `1.0.0` for the first submission and bump `CFBundleVersion` for every upload.
- Archive: Product > Archive in Xcode (or `xcodebuild -scheme Tagkollen archive`), then Distribute > App Store Connect. `ITSAppUsesNonExemptEncryption` is already `false`, so no export-compliance questions appear.
- `PrivacyInfo.xcprivacy` declares the required-reason API usage (UserDefaults, file timestamps); update it if new APIs are added.

## App Store Connect metadata (drafts)

**Name:** Tågkollen
**Subtitle (en):** Live trains across Sweden
**Underrubrik (sv):** Sveriges tåg i realtid
**Primary category:** Travel. **Secondary:** Navigation.
**Age rating:** 4+ (no objectionable content, no web browsing, no user-generated content).
**Price:** Free.
**Support URL:** <https://github.com/sebdanielsson/tagkollen/issues>
**Privacy policy URL:** <https://github.com/sebdanielsson/tagkollen/blob/main/PRIVACY.md>
**Marketing URL (optional):** <https://github.com/sebdanielsson/tagkollen>
**Copyright:** © 2026 Sebastian Danielsson. Licensed MIT.

**Keywords (en, ≤100 chars):** train,trains,Sweden,SJ,Trafikverket,delay,departures,railway,live map,timetable
**Nyckelord (sv):** tåg,tågtider,försening,avgångar,Trafikverket,SJ,järnväg,karta,tidtabell,pendeltåg

**Description (en):**

> See every train in Sweden live on a map, straight from Trafikverket's open data.
>
> • Live map of all trains with GPS positions, coloured by delay
> • Every stop of a train with planned, expected and actual times, tracks and disruption messages
> • Search by train number or station; departure and arrival boards
> • Save trains you plan to take and mark where you board and get off
> • Notifications for delays, cancellations, track changes and arrival, plus a departure reminder
> • Live Activities on the Lock Screen and in the Dynamic Island while you travel
> • Home Screen and Lock Screen widgets for a saved train or a station's departures
> • Swedish and English. No account, no ads, no tracking.
>
> Tågkollen is open source and not affiliated with Trafikverket. Data: Trafikverket Open API (CC0).

**Beskrivning (sv):**

> Se alla Sveriges tåg live på en karta, direkt från Trafikverkets öppna data.
>
> • Livekarta över alla tåg med GPS-position, färgade efter försening
> • Alla uppehåll för ett tåg med planerade, beräknade och verkliga tider, spår och trafikmeddelanden
> • Sök på tågnummer eller station; avgångs- och ankomsttavlor
> • Spara tåg du ska åka med och ange var du kliver på och av
> • Aviseringar om förseningar, inställda tåg, spårändringar och ankomst, samt påminnelse före avgång
> • Live Activities på låsskärmen och i Dynamic Island under resan
> • Widgetar för hemskärm och låsskärm med ett sparat tåg eller en stations avgångar
> • Svenska och engelska. Inget konto, inga annonser, ingen spårning.
>
> Tågkollen är öppen källkod och har ingen koppling till Trafikverket. Data: Trafikverkets öppna API (CC0).

**What's New (1.0.0):** First release.

## App Privacy questionnaire

Answer **"No, we do not collect data from this app."** The app has no backend and no analytics. Location, microphone and speech are processed on-device or by Apple's own services and never reach the developer; Trafikverket receives only anonymous API requests. This matches `PRIVACY.md`.

Permission strings already in `Info.plist` (Swedish): location when in use, microphone, speech recognition.

## Review notes

Paste into "Notes for review":

> Tågkollen shows public train data from Trafikverket's Open API. No login is required; a Trafikverket API key is bundled in the build. Location is optional and only centres the map. To see notifications and Live Activities, open a train and tap the star or the "Follow" button; alerts are generated on the device from the API data.

## Other checks

- [ ] Test on a real device: notifications (Settings > Notifications toggle), Live Activity, widgets, background refresh after the app has been in the background for a while.
- [ ] TestFlight round with a few users before submitting.
- [ ] Accessibility: Dynamic Type, VoiceOver labels on map controls and badges (`accessibilityLabel` exists on tracks and delay badges).
- [ ] Trademark: "Trafikverket" appears only as the data source with a non-affiliation note, and the red is a colour, not their logotype. Do not use the Trafikverket logotype anywhere.
