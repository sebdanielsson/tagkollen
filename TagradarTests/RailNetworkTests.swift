import Foundation
@testable import Tagradar
import Testing

/// `RailNetwork.parse(data:)` is the only code that turns the bundled JSON into a `RailGraph`, so
/// the wire format (`[lat, lon]` nodes, `[a, b, interior, length]` edges, `{signature: node}`
/// stations) is pinned here against a hand-written bundle, independent of the real 750 KB file.
@Suite("RailNetwork bundle parsing")
struct RailNetworkTests {
    static let bundle = """
    {"nodes":[[60.0,18.0],[60.2,18.0],[60.3,18.0]],
     "edges":[[0,1,[[60.1,18.05]],12345.6],[1,2,[],4000]],
     "stations":{"A":0,"B":1,"C":2}}
    """

    @Test("Decodes nodes, interior points, lengths and both traversal directions")
    func decodesBundle() throws {
        let graph = try RailNetwork.parse(data: Data(Self.bundle.utf8))
        #expect(graph.nodeCoordinates.count == 3)
        #expect(graph.edges.count == 2)
        #expect(graph.edges[0].points.map(\.latitude) == [60.0, 60.1, 60.2])
        #expect(graph.edges[0].points.map(\.longitude) == [18.0, 18.05, 18.0])
        #expect(graph.edges[0].length == 12345.6)
        #expect(graph.edges[1].points.count == 2)
        #expect(graph.adjacency[0].map(\.to) == [1])
        #expect(graph.adjacency[0].map(\.forward) == [true])
        #expect(graph.adjacency[1].map(\.to) == [0, 2])
        #expect(graph.adjacency[1].map(\.forward) == [false, true])
        #expect(graph.stationNode == ["A": 0, "B": 1, "C": 2])
        #expect(graph.route(from: "A", to: "C")?.map(\.latitude) == [60.0, 60.1, 60.2, 60.3])
        #expect(graph.route(from: "B", to: "A")?.map(\.latitude) == [60.2, 60.1, 60.0])
    }

    @Test("An edge pointing outside the node list throws instead of trapping")
    func rejectsEdgeWithBadNodeIndex() {
        let json = """
        {"nodes":[[60.0,18.0]],"edges":[[0,7,[],100]],"stations":{}}
        """
        #expect(throws: RailNetworkError.self) {
            try RailNetwork.parse(data: Data(json.utf8))
        }
    }

    @Test("A station pointing outside the node list throws instead of trapping")
    func rejectsStationWithBadNodeIndex() {
        let json = """
        {"nodes":[[60.0,18.0]],"edges":[],"stations":{"A":3}}
        """
        #expect(throws: RailNetworkError.self) {
            try RailNetwork.parse(data: Data(json.utf8))
        }
    }

    @Test("A coordinate that isn't a [lat, lon] pair throws")
    func rejectsMalformedCoordinate() {
        let json = """
        {"nodes":[[60.0]],"edges":[],"stations":{}}
        """
        #expect(throws: RailNetworkError.self) {
            try RailNetwork.parse(data: Data(json.utf8))
        }
    }

    @Test("A non-positive edge length throws")
    func rejectsNonPositiveLength() {
        let json = """
        {"nodes":[[60.0,18.0],[60.1,18.0]],"edges":[[0,1,[],0]],"stations":{}}
        """
        #expect(throws: RailNetworkError.self) {
            try RailNetwork.parse(data: Data(json.utf8))
        }
    }
}
