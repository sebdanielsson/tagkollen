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

@Suite("RailGraph routing")
struct RailGraphTests {
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
