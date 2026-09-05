import CoreLocation
import Foundation
import os

/// The real shape of the Swedish rail network, bundled offline from Trafikverket's National
/// Railway Database (NJDB, CC0), so routes can be drawn following actual track geometry instead
/// of straight lines between stations. Junctions are graph nodes; the long straight-ish runs
/// between them are collapsed into single edges carrying their simplified shape, so the whole
/// network is ~7k nodes/9k edges instead of ~400k raw survey points. See `docs/rail-network.md`
/// for how `RailNetwork.json` is generated from the NJDB GeoPackage.
@MainActor
final class RailNetwork {
    private struct Edge {
        let to: Int
        let points: [CLLocationCoordinate2D]
        let length: CLLocationDistance
    }

    private var nodeCoordinates: [CLLocationCoordinate2D] = []
    private var adjacency: [[Edge]] = []
    private var stationNode: [String: Int] = [:]
    private let logger = Logger(subsystem: "se.tagkollen.app", category: "RailNetwork")

    static let shared = RailNetwork()

    private init() {
        load()
    }

    /// The real-track path between two adjacent stops, or `nil` if either station isn't in the
    /// network (e.g. a foreign border station) or no path exists — callers fall back to a
    /// straight line in that case.
    func route(from: String, to: String) -> [CLLocationCoordinate2D]? {
        guard let start = stationNode[from], let goal = stationNode[to], start != goal else { return nil }
        guard let path = shortestPath(from: start, to: goal) else { return nil }
        return path
    }

    // MARK: Loading

    private func load() {
        guard let url = Bundle.main.url(forResource: "RailNetwork", withExtension: "json") else {
            logger.error("RailNetwork.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(RawNetwork.self, from: data)
            nodeCoordinates = raw.nodes.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            adjacency = Array(repeating: [], count: nodeCoordinates.count)
            for edge in raw.edges {
                var points = [nodeCoordinates[edge.a]]
                points.append(contentsOf: edge.interior.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) })
                points.append(nodeCoordinates[edge.b])
                let length = Self.length(of: points)
                adjacency[edge.a].append(Edge(to: edge.b, points: points, length: length))
                adjacency[edge.b].append(Edge(to: edge.a, points: points.reversed(), length: length))
            }
            stationNode = raw.stations
            let nodeCount = nodeCoordinates.count
            let stationCount = stationNode.count
            logger.debug("Loaded rail network: \(nodeCount) nodes, \(raw.edges.count) edges, \(stationCount) stations")
        } catch {
            logger.error("Failed to load RailNetwork.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func length(of points: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard points.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 0 ..< points.count - 1 {
            let a = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let b = CLLocation(latitude: points[i + 1].latitude, longitude: points[i + 1].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    // MARK: Dijkstra

    private func shortestPath(from start: Int, to goal: Int) -> [CLLocationCoordinate2D]? {
        var distance = [Int: CLLocationDistance]()
        var previousNode = [Int: Int]()
        var previousEdge = [Int: Edge]()
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
            for edge in adjacency[node] where !visited.contains(edge.to) {
                let candidate = base + edge.length
                if candidate < (distance[edge.to] ?? .infinity) {
                    distance[edge.to] = candidate
                    previousNode[edge.to] = node
                    previousEdge[edge.to] = edge
                    heap.insert(edge.to, priority: candidate)
                }
            }
        }
        guard distance[goal] != nil else { return nil }

        // Walk the predecessor chain back to `start`; each stored edge already runs from its
        // source node to the node it unlocked, so replaying them in order retraces the route.
        var chain: [Edge] = []
        var current = goal
        while current != start, let edge = previousEdge[current], let previous = previousNode[current] {
            chain.append(edge)
            current = previous
        }
        guard current == start else { return nil }
        chain.reverse()

        var result = [nodeCoordinates[start]]
        for edge in chain {
            result.append(contentsOf: edge.points.dropFirst())
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

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        a = try container.decode(Int.self)
        b = try container.decode(Int.self)
        interior = try container.decode([[Double]].self)
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
