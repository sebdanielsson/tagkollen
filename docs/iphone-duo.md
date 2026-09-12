# iPhone Duo and iOS 27

Status of Tågradar's readiness for iOS 27 and the foldable iPhone Duo, announced 2026-09-09 and shipping 2026-10-23.

## Toolchain status

The work splits cleanly in two, because the two targets need different toolchains and only one of them exists today.

| Target | Needs | Available as of 2026-09-12 |
| --- | --- | --- |
| iOS 27.0 | Xcode 27 (27A266a, RC) | Yes — released 2026-09-09 |
| iPhone Duo | Xcode 27.1 + iOS 27.1 SDK + Duo simulator | No — not yet released |

Xcode 27 requires macOS 26.4 or later on Apple silicon.

The iPhone Duo SDK, the `ReservedRegion` APIs and the Duo simulator all arrive with Xcode 27.1, expected late September 2026. Until then no Duo-specific code can be compiled or tested, and there is no hardware outside Apple. Everything in "Blocked on Xcode 27.1" below is deliberately not implemented yet.

## Audit result

The app is already well positioned, because it was written size-class-first rather than device-first. A sweep for the patterns Apple calls out in *Prepare your app for iPhone Duo* found no violations:

- No `UIScreen.main` anywhere — nothing assumes a single display.
- No `userInterfaceIdiom`, `UIDevice.current` or interface-orientation branching.
- Layout is driven by `horizontalSizeClass` in `MapScreen` and `TrainDetailView`. `RootView` does not branch on it at all, and `MapSheet` deliberately does not read it: a split-view sidebar column is compact width on every device, so it takes an explicit style from `MapScreen` instead. `StationBoardView` picks its navigation behaviour from whether a selection callback was supplied, not from the size class.
- One deliberate exception to size-class-only layout: the regular layout reads the window's own proportions to decide whether the sidebar is shown, because binding `columnVisibility` at all opts out of `NavigationSplitView`'s automatic behaviour and the sidebar would otherwise stay wherever the previous pose left it. This is the one place a pose change, rather than a size-class change, moves the layout, so it is worth re-checking against the real device.
- The regular-width layout is a `NavigationSplitView` (the card as a sidebar beside the map) with an `.inspector` for the selected train or station, so columns collapse, tile and overlay on their own across poses.
- `Info.plist` sets `UIApplicationSupportsMultipleScenes` and has no `UIRequiresFullScreen` and no orientation lock.
- Hard-coded `.frame(width:height:)` calls are fixed-size glyphs and hit targets (dots, 44 pt buttons) and a few narrow column widths in the stop timeline and the map card. None is derived from or assumes a screen size.

The inner display is **regular in both dimensions** and does not honour `UISupportedInterfaceOrientations`, so unfolding the device puts the app straight into the existing regular-width layout. That is the intended behaviour and needs no new code.

## Fixed: state reset when the layout switched

`RootView` used to choose between two structurally different subtrees:

```swift
Group {
    if sizeClass == .regular { tabs } else { phone }
}
```

`phone` hosted `MapScreen()` directly; `tabs` hosted it inside a `Tab` in a `TabView`. Those are different positions in the view tree, so SwiftUI treated them as different view identities. When the size class flips, the old `MapScreen` is destroyed and a new one is built with fresh `@State`, discarding `camera`, `visibleRegion`, `selectedTrainID`, `selectedKey`, `selectedStation`, `sheetDetent`, the card's trail (`sheetPath` and `navigationStack`) and any `deferredFocus`. The map snaps back to the whole-of-Sweden region, the selected train is lost and the card returns to its root.

This is not Duo-specific. iPhone Plus and Max models report a regular width in landscape, so rotating an iPhone 17 Pro Max already triggers it today.

It reproduced on an iPhone 17 Pro Max simulator: select a train, rotate to landscape with Cmd+Left or Cmd+Right, and the map reset to the whole country. `TagradarUITests` now covers the same transition.

On iPhone Duo this stops being an edge case and becomes a core interaction — every open and close of the device crosses the same boundary.

### Fix

The map's durable state — camera, visible region, selection, the card's trail and its detent, and any deferred focus — now lives in `MapState` (`Tagradar/Views/Map/MapState.swift`), an `@Observable` model owned by `RootView` as `@State` and injected with `.environment(mapState)`, exactly the way `AppNavigation` already is. `RootView` never changes identity, so the object survives the swap and each freshly built `MapScreen` picks up where the last one left off. Neither layout changed; `MapScreen` reads and writes `mapState.…` instead of its own `@State`.

Selecting in the regular layout does not push onto the card's trail (there is no card), so a preserved trail could lag the selection: closing a Duo after picking a different train on the inner display would leave the card on whatever it showed before the device opened. `MapScreen` therefore reconciles when the size class becomes compact, appending the current selection to the trail so the card and the map agree and "back" still returns to what the card showed before.

The iPad redesign that followed removed the tabs altogether: `RootView` no longer branches on size class, `MapScreen` is the single root and swaps its own compact and regular layouts. `MapState` stays where it is, because the views inside those layouts are still rebuilt on the flip.

## Blocked on Xcode 27.1

Not implemented, because the SDK that defines them does not exist yet:

- `ReservedRegion` (SwiftUI) / `UIViewReservedRegion` (UIKit) — lets custom UI claim maximum space without colliding with system UI. Relevant to the map overlays and `MapControlsCluster`.
- Building against the iOS 27.1 SDK changes behaviour on the inner display: content reaches the screen edge, and standard navigation and toolbar buttons lay out vertically rather than horizontally.
- Concentricity (`ConcentricRectangle`, `UICornerConfiguration`) is iOS 26 and already available, but is best tuned against the real corner radii of the Duo's two displays.
- Verify all four poses in the Duo simulator in DeviceHub, which has on-screen open, close, rotate and fold controls.
- Verify the widgets and Live Activity on the cover display.

## CI

`.github/workflows/ci.yml` runs on the `macos-26` runner image and does not pin an Xcode version, so it builds with whatever Xcode is default on the image. When GitHub flips that default to Xcode 27 the SDK changes silently. Pinning the Xcode version explicitly would make that transition deliberate rather than incidental.

## Sources

- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) — Apple Tech Talk
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) — Human Interface Guidelines
- [Apple Developer releases](https://developer.apple.com/news/releases/) — toolchain availability
