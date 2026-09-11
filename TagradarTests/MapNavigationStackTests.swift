import Foundation
@testable import Tagradar
import Testing
import TrafikverketKit

@Suite("MapNavigationStack")
struct MapNavigationStackTests {
    private let cst = TrainKey(ident: "Cst-train", departureDate: TRVDateParserBridge.date(fromDay: "2026-09-06")!)
    private let mora = TrainKey(ident: "Mora-train", departureDate: TRVDateParserBridge.date(fromDay: "2026-09-06")!)

    private func station(_ signature: String, name: String = "Station") throws -> TrainStation {
        let json = Data(#"{"LocationSignature":"\#(signature)","AdvertisedLocationName":"\#(name)"}"#.utf8)
        return try JSONDecoder.trafikverket.decode(TrainStation.self, from: json)
    }

    @Test("Pushing a new route appends it and becomes the top")
    func pushAppendsNewRoute() {
        var stack = MapNavigationStack()
        let pushed = stack.push(.train(TrainSelection(key: cst, liveID: "123")))
        #expect(pushed)
        #expect(stack.top == .train(TrainSelection(key: cst, liveID: "123")))
        #expect(stack.routes.count == 1)
    }

    @Test("Pushing the same route already on top is a no-op — no duplicate, e.g. a repeat tap")
    func pushSkipsDuplicateOfTop() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        let pushedAgain = try stack.push(.station(station("Cst")))
        #expect(!pushedAgain)
        #expect(stack.routes.count == 1)
    }

    @Test("Pushing a different route on top of an existing one grows the stack")
    func pushGrowsOntoExistingRoute() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        let pushed = stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        #expect(pushed)
        #expect(stack.routes.count == 2)
        #expect(stack.top == .train(TrainSelection(key: cst, liveID: nil)))
    }

    @Test("Trimming to a shorter count reveals the previous route underneath — the 'back' case")
    func trimRevealsPreviousRoute() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        let top = stack.trim(to: 1)
        #expect(try top == .station(station("Cst")))
        #expect(stack.routes.count == 1)
    }

    @Test("Trimming all the way down reveals nothing")
    func trimToEmptyRevealsNil() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        let top = stack.trim(to: 0)
        #expect(top == nil)
        #expect(stack.isEmpty)
    }

    @Test("Trimming to a count that isn't smaller than the current size changes nothing")
    func trimIsNoOpWhenNotShrinking() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: mora, liveID: nil)))
        let top = stack.trim(to: 2)
        #expect(top == .train(TrainSelection(key: mora, liveID: nil)))
        #expect(stack.routes.count == 2)
    }

    @Test("A fresh stack is empty")
    func freshStackIsEmpty() {
        let stack = MapNavigationStack()
        #expect(stack.isEmpty)
        #expect(stack.top == nil)
    }

    @Test("The same train counts as the same screen once it starts reporting a live position")
    func pushSkipsSameTrainWithNewLiveID() {
        var stack = MapNavigationStack()
        stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        // The train was selected before it had a position; now it has one. Same screen, so this
        // must not push a second copy of the detail on top of the first.
        let pushedAgain = stack.push(.train(TrainSelection(key: cst, liveID: "123")))
        #expect(!pushedAgain)
        #expect(stack.routes.count == 1)
    }

    @Test("A station is the same screen even if the directory refreshed its details")
    func pushSkipsSameStationWithDifferentDetails() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst", name: "Stockholm C")))
        // Same station, re-fetched with a different advertised name: still one screen.
        let pushedAgain = try stack.push(.station(station("Cst", name: "Stockholm Central")))
        #expect(!pushedAgain)
        #expect(stack.routes.count == 1)
    }

    @Test("A train with no number is identified by its live id, so a different one still pushes")
    func keylessTrainsCompareByLiveID() {
        var stack = MapNavigationStack()
        // Freight and service trains have no advertised number, so no key to compare.
        stack.push(.train(TrainSelection(key: nil, liveID: "freight-1")))
        let pushedSame = stack.push(.train(TrainSelection(key: nil, liveID: "freight-1")))
        let pushedOther = stack.push(.train(TrainSelection(key: nil, liveID: "freight-2")))
        #expect(!pushedSame)
        #expect(pushedOther)
        #expect(stack.routes.count == 2)
    }

    @Test("A route already in the stack, but not on top, still pushes")
    func pushAllowsRouteRepeatedDeeper() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        // Cst -> a train -> Cst again: the user is three screens deep, not back at the first one.
        let pushed = try stack.push(.station(station("Cst")))
        #expect(pushed)
        #expect(stack.routes.count == 3)
        #expect(try stack.top == .station(station("Cst")))
    }

    @Test("Trimming past the bottom of the stack leaves it alone")
    func trimBeyondSizeIsIgnored() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: mora, liveID: nil)))
        let top = stack.trim(to: 5)
        #expect(top == .train(TrainSelection(key: mora, liveID: nil)))
        #expect(stack.routes.count == 2)
    }

    @Test("Trimming an empty stack reveals nothing")
    func trimOnEmptyStack() {
        var stack = MapNavigationStack()
        #expect(stack.trim(to: 0) == nil)
        #expect(stack.isEmpty)
    }

    @Test("Re-pushing a train after backing out of it works — the screen below is a different one")
    func pushAfterTrimReopensTheSameTrain() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: cst, liveID: "123")))
        stack.trim(to: 1)
        let pushed = stack.push(.train(TrainSelection(key: cst, liveID: "123")))
        #expect(pushed)
        #expect(stack.routes.count == 2)
    }

    @Test("Reset clears the stack entirely")
    func resetClears() throws {
        var stack = MapNavigationStack()
        try stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: mora, liveID: nil)))
        stack.reset()
        #expect(stack.isEmpty)
        #expect(stack.top == nil)
    }
}
