import CoreLocation
@testable import Tagkollen
import Testing

/// Small synthetic network, independent of the real bundled data:
///
/// ```
///        A(0) --5-- J(1) --5-- B(2) --4-- C(3)
///          \_____________3_____/
///                (via M)
/// ```
///
/// `A→B` has two paths: 10 via the junction `J`, or 3 direct via `M` — the direct one should
/// always win. `D(4)` has no edges, so it's reachable by signature but not by track.
enum RailGraphFixture {
    static let a = CLLocationCoordinate2D(latitude: 60.0, longitude: 18.0)
    static let j = CLLocationCoordinate2D(latitude: 60.1, longitude: 18.0)
    static let b = CLLocationCoordinate2D(latitude: 60.2, longitude: 18.0)
    static let c = CLLocationCoordinate2D(latitude: 60.3, longitude: 18.0)
    static let d = CLLocationCoordinate2D(latitude: 61.0, longitude: 18.0)
    static let m = CLLocationCoordinate2D(latitude: 60.15, longitude: 18.05)

    /// Node indices: 0=A, 1=J, 2=B, 3=C, 4=D (isolated).
    static let graph = RailGraph(
        nodeCoordinates: [a, j, b, c, d],
        edges: [
            RailGraph.Edge(points: [a, j], length: 5),
            RailGraph.Edge(points: [j, b], length: 5),
            RailGraph.Edge(points: [a, m, b], length: 3),
            RailGraph.Edge(points: [b, c], length: 4),
        ],
        adjacency: [
            [ // A(0)
                RailGraph.Adjacency(to: 1, edgeIndex: 0, forward: true),
                RailGraph.Adjacency(to: 2, edgeIndex: 2, forward: true),
            ],
            [ // J(1)
                RailGraph.Adjacency(to: 0, edgeIndex: 0, forward: false),
                RailGraph.Adjacency(to: 2, edgeIndex: 1, forward: true),
            ],
            [ // B(2)
                RailGraph.Adjacency(to: 1, edgeIndex: 1, forward: false),
                RailGraph.Adjacency(to: 0, edgeIndex: 2, forward: false),
                RailGraph.Adjacency(to: 3, edgeIndex: 3, forward: true),
            ],
            [ // C(3)
                RailGraph.Adjacency(to: 2, edgeIndex: 3, forward: false),
            ],
            [], // D(4) — isolated
        ],
        stationNode: ["A": 0, "B": 2, "C": 3, "D": 4]
    )
}

/// Three nodes where the direct A–B edge is discovered first (it's listed first in A's adjacency)
/// but the two short hops via X are cheaper. Only a correctly ordered heap pops X before the
/// already-queued B, so this pins the priority queue, not just the relaxation logic.
enum RailGraphDetourFixture {
    static let a = CLLocationCoordinate2D(latitude: 59.0, longitude: 18.0)
    static let x = CLLocationCoordinate2D(latitude: 59.1, longitude: 18.1)
    static let b = CLLocationCoordinate2D(latitude: 59.2, longitude: 18.0)

    static let graph = RailGraph(
        nodeCoordinates: [a, x, b],
        edges: [
            RailGraph.Edge(points: [a, b], length: 10),
            RailGraph.Edge(points: [a, x], length: 1),
            RailGraph.Edge(points: [x, b], length: 1),
        ],
        adjacency: [
            [RailGraph.Adjacency(to: 2, edgeIndex: 0, forward: true), RailGraph.Adjacency(to: 1, edgeIndex: 1, forward: true)],
            [RailGraph.Adjacency(to: 0, edgeIndex: 1, forward: false), RailGraph.Adjacency(to: 2, edgeIndex: 2, forward: true)],
            [RailGraph.Adjacency(to: 0, edgeIndex: 0, forward: false), RailGraph.Adjacency(to: 1, edgeIndex: 2, forward: false)],
        ],
        stationNode: ["A": 0, "B": 2]
    )
}

private func coordinates(_ route: [CLLocationCoordinate2D]?) -> [[Double]]? {
    route?.map { [$0.latitude, $0.longitude] }
}

@Suite("RailGraph routing")
struct RailGraphTests {
    @Test("Improves on a longer path that was queued first")
    func improvesOnEarlierQueuedPath() {
        let route = RailGraphDetourFixture.graph.route(from: "A", to: "B")
        let expected = [RailGraphDetourFixture.a, RailGraphDetourFixture.x, RailGraphDetourFixture.b]
        #expect(coordinates(route) == coordinates(expected))
    }

    @Test("Picks the shorter direct edge over a longer path through a junction")
    func prefersShortestPath() {
        let route = RailGraphFixture.graph.route(from: "A", to: "B")
        #expect(route?.map(\.latitude) == [RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b].map(\.latitude))
        #expect(route?.map(\.longitude) == [RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b].map(\.longitude))
    }

    @Test("Stitches consecutive edges across a multi-hop route")
    func stitchesMultiHopRoute() {
        let route = RailGraphFixture.graph.route(from: "A", to: "C")
        let expected = [RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b, RailGraphFixture.c]
        #expect(route?.map(\.latitude) == expected.map(\.latitude))
        #expect(route?.map(\.longitude) == expected.map(\.longitude))
    }

    @Test("Reversing the query reverses the polyline instead of duplicating it")
    func reversesPolylineForOppositeDirection() {
        let route = RailGraphFixture.graph.route(from: "B", to: "A")
        let expected = [RailGraphFixture.b, RailGraphFixture.m, RailGraphFixture.a]
        #expect(route?.map(\.latitude) == expected.map(\.latitude))
        #expect(route?.map(\.longitude) == expected.map(\.longitude))
    }

    @Test("An unknown station signature has no route")
    func unknownStationReturnsNil() {
        #expect(RailGraphFixture.graph.route(from: "A", to: "Z") == nil)
    }

    @Test("The same station as both ends has no route")
    func sameStationReturnsNil() {
        #expect(RailGraphFixture.graph.route(from: "A", to: "A") == nil)
    }

    @Test("A station with no edges is unreachable even though its signature is known")
    func unreachableStationReturnsNil() {
        #expect(RailGraphFixture.graph.route(from: "A", to: "D") == nil)
    }
}

@Suite("Route polyline stitching")
struct RailGraphPolylineTests {
    typealias Stop = (signature: String, coordinate: CLLocationCoordinate2D)

    /// A station's directory coordinate deliberately differs from its track node, as it does for
    /// real stations that snap a few hundred metres off.
    static let aDirectory = CLLocationCoordinate2D(latitude: 60.001, longitude: 18.001)
    static let cDirectory = CLLocationCoordinate2D(latitude: 60.301, longitude: 18.001)
    static let z = CLLocationCoordinate2D(latitude: 62.0, longitude: 20.0)

    private func stitch(_ stops: [Stop]) -> [[Double]]? {
        coordinates(RailGraph.polyline(through: stops, route: RailGraphFixture.graph.route))
    }

    @Test("Consecutive real segments share their joining node exactly once")
    func joinsRealSegmentsWithoutDuplicates() {
        let stops: [Stop] = [("A", Self.aDirectory), ("B", RailGraphFixture.b), ("C", Self.cDirectory)]
        let expected = [RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b, RailGraphFixture.c]
        #expect(stitch(stops) == coordinates(expected))
    }

    @Test("Falls back to the stations' own coordinates when nothing is routable")
    func fallsBackToStraightSegments() {
        let stops: [Stop] = [("Z", Self.z), ("Y", Self.aDirectory)]
        #expect(stitch(stops) == coordinates([Self.z, Self.aDirectory]))
    }

    @Test("A real segment after a fallback starts on its own track node, not the previous point")
    func realSegmentAfterFallbackKeepsItsFirstNode() {
        let stops: [Stop] = [("Z", Self.z), ("A", Self.aDirectory), ("B", RailGraphFixture.b)]
        let expected = [Self.z, Self.aDirectory, RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b]
        #expect(stitch(stops) == coordinates(expected))
    }

    @Test("A fallback after a real segment continues from the track node")
    func fallbackAfterRealSegment() {
        let stops: [Stop] = [("A", Self.aDirectory), ("B", RailGraphFixture.b), ("Z", Self.z)]
        let expected = [RailGraphFixture.a, RailGraphFixture.m, RailGraphFixture.b, Self.z]
        #expect(stitch(stops) == coordinates(expected))
    }

    @Test("A single stop has no line")
    func singleStopIsEmpty() {
        #expect(stitch([("A", Self.aDirectory)]) == [])
    }
}
