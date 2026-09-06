import Foundation
@testable import Tagkollen
import Testing
import TrafikverketKit

@Suite("MapNavigationStack")
struct MapNavigationStackTests {
    private let cst = TrainKey(ident: "Cst-train", departureDate: TRVDateParserBridge.date(fromDay: "2026-09-06")!)
    private let mora = TrainKey(ident: "Mora-train", departureDate: TRVDateParserBridge.date(fromDay: "2026-09-06")!)

    private func station(_ signature: String) -> TrainStation {
        let json: [String: Any] = ["LocationSignature": signature]
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        return try! JSONDecoder.trafikverket.decode(TrainStation.self, from: data) // swiftlint:disable:this force_try
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
    func pushSkipsDuplicateOfTop() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        let pushedAgain = stack.push(.station(station("Cst")))
        #expect(!pushedAgain)
        #expect(stack.routes.count == 1)
    }

    @Test("Pushing a different route on top of an existing one grows the stack")
    func pushGrowsOntoExistingRoute() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        let pushed = stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        #expect(pushed)
        #expect(stack.routes.count == 2)
        #expect(stack.top == .train(TrainSelection(key: cst, liveID: nil)))
    }

    @Test("Trimming to a shorter count reveals the previous route underneath — the 'back' case")
    func trimRevealsPreviousRoute() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: cst, liveID: nil)))
        let top = stack.trim(to: 1)
        #expect(top == .station(station("Cst")))
        #expect(stack.routes.count == 1)
    }

    @Test("Trimming all the way down reveals nothing")
    func trimToEmptyRevealsNil() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        let top = stack.trim(to: 0)
        #expect(top == nil)
        #expect(stack.isEmpty)
    }

    @Test("Trimming to a count that isn't smaller than the current size changes nothing")
    func trimIsNoOpWhenNotShrinking() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: mora, liveID: nil)))
        let top = stack.trim(to: 2)
        #expect(top == .train(TrainSelection(key: mora, liveID: nil)))
        #expect(stack.routes.count == 2)
    }

    @Test("Reset clears the stack entirely")
    func resetClears() {
        var stack = MapNavigationStack()
        stack.push(.station(station("Cst")))
        stack.push(.train(TrainSelection(key: mora, liveID: nil)))
        stack.reset()
        #expect(stack.isEmpty)
        #expect(stack.top == nil)
    }
}
