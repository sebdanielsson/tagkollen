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
/// Parsing the bundled JSON is done off the main actor and kicked off eagerly at launch (see
/// `AppDependencies`), not lazily on first use, so it isn't competing for the main thread on the
/// exact frame a user taps a train. `route(from:to:)` simply returns `nil` (straight-line
/// fallback) until loading finishes.
@MainActor
@Observable
final class RailNetwork {
    private struct Edge {
        /// Always stored source → destination as laid out in the bundle; `Adjacency.forward`
        /// says whether a given traversal needs to walk it in that order or reversed, so the
        /// polyline itself is never duplicated for the two directions.
        let points: [CLLocationCoordinate2D]
        let length: CLLocationDistance
    }

    private struct Adjacency {
        let to: Int
        let edgeIndex: Int
        let forward: Bool
    }

    private struct ParsedNetwork: Sendable {
        let nodes: [CLLocationCoordinate2D]
        let edges: [Edge]
        let adjacency: [[Adjacency]]
        let stations: [String: Int]
    }

    private(set) var isLoaded = false
    private var nodeCoordinates: [CLLocationCoordinate2D] = []
    private var edges: [Edge] = []
    private var adjacency: [[Adjacency]] = []
    private var stationNode: [String: Int] = [:]
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
        guard isLoaded, let start = stationNode[from], let goal = stationNode[to], start != goal else { return nil }
        let key = "\(from)|\(to)"
        if let cached = routeCache[key] {
            return cached
        }
        let path = shortestPath(from: start, to: goal)
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
            nodeCoordinates = parsed.nodes
            edges = parsed.edges
            adjacency = parsed.adjacency
            stationNode = parsed.stations
            isLoaded = true
            let nodeCount = parsed.nodes.count
            let edgeCount = parsed.edges.count
            let stationCount = parsed.stations.count
            logger.debug("Loaded rail network: \(nodeCount) nodes, \(edgeCount) edges, \(stationCount) stations")
        } catch {
            logger.error("Failed to load RailNetwork.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pure parsing, off the main actor: JSON decode plus building the adjacency list. Edge
    /// lengths come straight from the bundle (computed once, offline, in export_network.py) — no
    /// per-edge CLLocation distance calculations here.
    private nonisolated static func parse(url: URL) throws -> ParsedNetwork {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(RawNetwork.self, from: data)
        let nodes = raw.nodes.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }

        var edges: [Edge] = []
        edges.reserveCapacity(raw.edges.count)
        var adjacency = Array(repeating: [Adjacency](), count: nodes.count)
        for rawEdge in raw.edges {
            var points = [nodes[rawEdge.a]]
            points.append(contentsOf: rawEdge.interior.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) })
            points.append(nodes[rawEdge.b])
            let edgeIndex = edges.count
            edges.append(Edge(points: points, length: rawEdge.length))
            adjacency[rawEdge.a].append(Adjacency(to: rawEdge.b, edgeIndex: edgeIndex, forward: true))
            adjacency[rawEdge.b].append(Adjacency(to: rawEdge.a, edgeIndex: edgeIndex, forward: false))
        }
        return ParsedNetwork(nodes: nodes, edges: edges, adjacency: adjacency, stations: raw.stations)
    }

    // MARK: Dijkstra

    private func shortestPath(from start: Int, to goal: Int) -> [CLLocationCoordinate2D]? {
        var distance = [Int: CLLocationDistance]()
        var previousNode = [Int: Int]()
        var previousAdjacency = [Int: Adjacency]()
        var visited = Set<Int>()
        var heap = MinHeap<Int>()

        distance[start] = 0
        heap.insert(start, priority: 0)

        while let node = heap.popMin() {
            guard !visited.contains(node) else { continue }
            visited.insert(node)
            if node == goal {
                break
            }
            let base = distance[node] ?? .infinity
            for step in adjacency[node] where !visited.contains(step.to) {
                let candidate = base + edges[step.edgeIndex].length
                if candidate < (distance[step.to] ?? .infinity) {
                    distance[step.to] = candidate
                    previousNode[step.to] = node
                    previousAdjacency[step.to] = step
                    heap.insert(step.to, priority: candidate)
                }
            }
        }
        guard distance[goal] != nil else { return nil }

        // Walk the predecessor chain back to `start`, then replay each step's edge in the
        // direction it was actually traversed to retrace the route forward.
        var steps: [Adjacency] = []
        var current = goal
        while current != start, let step = previousAdjacency[current], let previous = previousNode[current] {
            steps.append(step)
            current = previous
        }
        guard current == start else { return nil }
        steps.reverse()

        var result = [nodeCoordinates[start]]
        for step in steps {
            let points = edges[step.edgeIndex].points
            if step.forward {
                result.append(contentsOf: points.dropFirst())
            } else {
                result.append(contentsOf: points.dropLast().reversed())
            }
        }
        return result
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

/// Minimal binary min-heap keyed by priority, just enough for Dijkstra over a ~7k node graph.
private struct MinHeap<Element> {
    private var items: [(element: Element, priority: CLLocationDistance)] = []

    var isEmpty: Bool {
        items.isEmpty
    }

    mutating func insert(_ element: Element, priority: CLLocationDistance) {
        items.append((element, priority))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].priority < items[parent].priority else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func popMin() -> Element? {
        guard !items.isEmpty else { return nil }
        let root = items[0].element
        items[0] = items[items.count - 1]
        items.removeLast()
        var i = 0
        while true {
            let left = 2 * i + 1, right = 2 * i + 2
            var smallest = i
            if left < items.count, items[left].priority < items[smallest].priority {
                smallest = left
            }
            if right < items.count, items[right].priority < items[smallest].priority {
                smallest = right
            }
            guard smallest != i else { break }
            items.swapAt(i, smallest)
            i = smallest
        }
        return root
    }
}
