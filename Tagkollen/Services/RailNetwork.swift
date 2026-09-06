import CoreLocation
import Foundation
import os

/// The real shape of the Swedish rail network, bundled offline from Trafikverket's National
/// Railway Database (NJDB, CC0), so routes can be drawn following actual track geometry instead
/// of straight lines between stations. Junctions are graph nodes; the long straight-ish runs
/// between them are collapsed into single edges carrying their simplified shape, so the whole
/// network is ~7k nodes/9k edges instead of ~400k raw survey points. See `docs/rail-network.md`
/// for how `RailNetwork.json` is generated from the NJDB GeoPackage.
///
/// Owns loading and caching; the graph data structure and Dijkstra search themselves live in
/// `RailGraph`, which is tested directly against a small synthetic graph (`RailGraphTests`)
/// rather than through this bundle-loading, actor-isolated wrapper.
///
/// Parsing the bundled JSON is done off the main actor and kicked off eagerly at launch (see
/// `AppDependencies`), not lazily on first use, so it isn't competing for the main thread on the
/// exact frame a user taps a train. `route(from:to:)` simply returns `nil` (straight-line
/// fallback) until loading finishes.
@MainActor
@Observable
final class RailNetwork {
    private(set) var isLoaded = false
    private var graph: RailGraph?
    /// Consecutive stop pairs repeat heavily across different trains sharing the same line, so a
    /// warm cache makes re-selecting an already-seen pair instant.
    private var routeCache: [String: [CLLocationCoordinate2D]?] = [:]
    private let logger = Logger(subsystem: "se.tagkollen.app", category: "RailNetwork")

    static let shared = RailNetwork()

    private init() {}

    /// Kicks off parsing the bundled network on a background task. Call once, early (see
    /// `AppDependencies`) — safe to call more than once, later calls are no-ops while loading or
    /// once loaded.
    func preload() {
        guard !isLoaded else { return }
        Task { [weak self] in
            await self?.load()
        }
    }

    /// The real-track path between two adjacent stops, or `nil` if either station isn't in the
    /// network (e.g. a foreign border station), the network hasn't finished loading yet, or no
    /// path exists — callers fall back to a straight line in that case.
    func route(from: String, to: String) -> [CLLocationCoordinate2D]? {
        guard let graph else { return nil }
        let key = "\(from)|\(to)"
        if let cached = routeCache[key] {
            return cached
        }
        let path = graph.route(from: from, to: to)
        routeCache[key] = .some(path)
        return path
    }

    // MARK: Loading

    private func load() async {
        guard let url = Bundle.main.url(forResource: "RailNetwork", withExtension: "json") else {
            logger.error("RailNetwork.json not found in bundle")
            return
        }
        do {
            let parsed = try await Task.detached(priority: .utility) {
                try Self.parse(url: url)
            }.value
            graph = parsed
            isLoaded = true
            let nodeCount = parsed.nodeCoordinates.count
            let edgeCount = parsed.edges.count
            let stationCount = parsed.stationNode.count
            logger.debug("Loaded rail network: \(nodeCount) nodes, \(edgeCount) edges, \(stationCount) stations")
        } catch {
            logger.error("Failed to load RailNetwork.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pure parsing, off the main actor: JSON decode plus building the adjacency list. Edge
    /// lengths come straight from the bundle (computed once, offline, in export_network.py) — no
    /// per-edge CLLocation distance calculations here.
    private nonisolated static func parse(url: URL) throws -> RailGraph {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(RawNetwork.self, from: data)
        let nodes = raw.nodes.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }

        var edges: [RailGraph.Edge] = []
        edges.reserveCapacity(raw.edges.count)
        var adjacency = Array(repeating: [RailGraph.Adjacency](), count: nodes.count)
        for rawEdge in raw.edges {
            var points = [nodes[rawEdge.a]]
            points.append(contentsOf: rawEdge.interior.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) })
            points.append(nodes[rawEdge.b])
            let edgeIndex = edges.count
            edges.append(RailGraph.Edge(points: points, length: rawEdge.length))
            adjacency[rawEdge.a].append(RailGraph.Adjacency(to: rawEdge.b, edgeIndex: edgeIndex, forward: true))
            adjacency[rawEdge.b].append(RailGraph.Adjacency(to: rawEdge.a, edgeIndex: edgeIndex, forward: false))
        }
        return RailGraph(nodeCoordinates: nodes, edges: edges, adjacency: adjacency, stationNode: raw.stations)
    }
}

private struct RawNetwork: Decodable {
    let nodes: [[Double]]
    let edges: [RawEdge]
    let stations: [String: Int]
}

private struct RawEdge: Decodable {
    let a: Int
    let b: Int
    let interior: [[Double]]
    let length: Double

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        a = try container.decode(Int.self)
        b = try container.decode(Int.self)
        interior = try container.decode([[Double]].self)
        length = try container.decode(Double.self)
    }
}
