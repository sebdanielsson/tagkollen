/// Pure decision logic for `MapScreen`'s sheet navigation: a typed shadow of `sheetPath`'s
/// contents, kept separate from the view so it's unit-testable without a live SwiftUI
/// environment. `NavigationPath` is intentionally opaque (write-only — it can't be read back to
/// see what's on top after a pop), which is exactly the information restoring the map's selection
/// after "back" needs, hence keeping this typed copy in lockstep with every push.
struct MapNavigationStack {
    private(set) var routes: [MapSheetRoute] = []

    var top: MapSheetRoute? {
        routes.last
    }

    var isEmpty: Bool {
        routes.isEmpty
    }

    /// Pushes `route` unless it already addresses the screen on top (a repeat tap on the same
    /// train/station, or the same change a `trim(to:)` restore just re-applied). Returns whether
    /// it actually pushed, so the caller knows whether to also append to `sheetPath` and change
    /// the sheet detent.
    @discardableResult
    mutating func push(_ route: MapSheetRoute) -> Bool {
        if let last = routes.last, Self.addressSameScreen(last, route) {
            return false
        }
        routes.append(route)
        return true
    }

    /// Whether two routes open the same screen — which is not the same as being equal values. A
    /// train is identified by its `TrainKey`, not by the `liveID` that happened to be known when
    /// it was pushed: a train selected before it reported a position, and the same train once it
    /// has one, are one screen, and treating them as two pushed a duplicate copy on top of it.
    /// Stations likewise compare by signature, so a directory refresh can't make a station look
    /// like a different one. The trade-off is that two units reporting positions under one train
    /// number (a coupled service) count as one screen; re-selecting the other unit moves the map
    /// without pushing a second detail, which is the lesser of the two surprises.
    private static func addressSameScreen(_ lhs: MapSheetRoute, _ rhs: MapSheetRoute) -> Bool {
        switch (lhs, rhs) {
        case let (.train(a), .train(b)):
            if let keyA = a.key, let keyB = b.key {
                return keyA == keyB
            }
            return a == b
        case let (.station(a), .station(b)):
            return a.locationSignature == b.locationSignature
        default:
            return false
        }
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
