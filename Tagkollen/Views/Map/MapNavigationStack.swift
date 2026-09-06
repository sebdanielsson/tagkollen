/// Pure decision logic for `MapScreen`'s sheet navigation: a typed shadow of `sheetPath`'s
/// contents, kept separate from the view so it's unit-testable without a live SwiftUI
/// environment. `NavigationPath` is intentionally opaque (write-only — it can't be read back to
/// see what's on top after a pop), which is exactly the information restoring the map's selection
/// after "back" needs, hence keeping this typed copy in lockstep with every push.
struct MapNavigationStack: Equatable {
    private(set) var routes: [MapSheetRoute] = []

    var top: MapSheetRoute? {
        routes.last
    }

    var isEmpty: Bool {
        routes.isEmpty
    }

    /// Pushes `route` unless it's already on top (a repeat tap on the same train/station, or the
    /// same change a `trim(to:)` restore just re-applied). Returns whether it actually pushed, so
    /// the caller knows whether to also append to `sheetPath` and change the sheet detent.
    @discardableResult
    mutating func push(_ route: MapSheetRoute) -> Bool {
        guard routes.last != route else { return false }
        routes.append(route)
        return true
    }

    /// Call after `sheetPath` shrinks (the user tapped "back") to trim the shadow to match and
    /// find out what's now on top. A no-op, returning the current top unchanged, if `count` isn't
    /// actually smaller than what's already here.
    @discardableResult
    mutating func trim(to count: Int) -> MapSheetRoute? {
        guard count < routes.count else { return top }
        routes.removeLast(routes.count - count)
        return top
    }

    mutating func reset() {
        routes = []
    }
}
