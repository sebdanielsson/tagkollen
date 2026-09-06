import CoreLocation

/// Pure rail network data plus shortest-path search, independent of how it's loaded or cached.
/// Kept separate from `RailNetwork` so it can be constructed directly from a small synthetic
/// graph in tests instead of the real ~7k-node bundle.
struct RailGraph: Sendable {
    struct Edge: Sendable {
        /// Always stored source → destination as laid out by whoever builds the graph;
        /// `Adjacency.forward` says whether a given traversal needs to walk it in that order or
        /// reversed, so the polyline itself is never duplicated for the two directions.
        let points: [CLLocationCoordinate2D]
        let length: CLLocationDistance
    }

    struct Adjacency: Sendable {
        let to: Int
        let edgeIndex: Int
        let forward: Bool
    }

    let nodeCoordinates: [CLLocationCoordinate2D]
    let edges: [Edge]
    let adjacency: [[Adjacency]]
    let stationNode: [String: Int]

    /// Where a station sits on the track: the graph node it was snapped to, which is where every
    /// route through it starts and ends. `nil` for a signature the network doesn't know.
    func stationCoordinate(_ signature: String) -> CLLocationCoordinate2D? {
        stationNode[signature].map { nodeCoordinates[$0] }
    }

    /// The real-track path between two stations, or `nil` if either signature isn't in the
    /// network, they're the same station, or no path connects them.
    func route(from: String, to: String) -> [CLLocationCoordinate2D]? {
        guard let start = stationNode[from], let goal = stationNode[to], start != goal else { return nil }
        return shortestPath(from: start, to: goal)
    }

    /// Plain Dijkstra with flat, node-indexed arrays for its working state — no hashing for a graph
    /// this small — so the cold-cache worst case (a sparse-stop express flooding most of the
    /// network) stays well under a frame on the main actor.
    private func shortestPath(from start: Int, to goal: Int) -> [CLLocationCoordinate2D]? {
        let count = nodeCoordinates.count
        var distance = [CLLocationDistance](repeating: .infinity, count: count)
        var previousNode = [Int](repeating: -1, count: count)
        var previousAdjacency = [Adjacency?](repeating: nil, count: count)
        var visited = [Bool](repeating: false, count: count)
        var heap = MinHeap<Int>()

        distance[start] = 0
        heap.insert(start, priority: 0)

        while let node = heap.popMin() {
            guard !visited[node] else { continue }
            visited[node] = true
            if node == goal {
                break
            }
            let base = distance[node]
            for step in adjacency[node] where !visited[step.to] {
                let candidate = base + edges[step.edgeIndex].length
                if candidate < distance[step.to] {
                    distance[step.to] = candidate
                    previousNode[step.to] = node
                    previousAdjacency[step.to] = step
                    heap.insert(step.to, priority: candidate)
                }
            }
        }
        guard distance[goal] < .infinity else { return nil }

        // Walk the predecessor chain back to `start`, then replay each step's edge in the
        // direction it was actually traversed to retrace the route forward.
        var steps: [Adjacency] = []
        var current = goal
        while current != start, let step = previousAdjacency[current] {
            steps.append(step)
            current = previousNode[current]
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

extension RailGraph {
    /// Stitches a journey's consecutive stop pairs into one polyline: the real track shape where
    /// `route` knows it, a straight segment between the stops' given coordinates where it doesn't
    /// (foreign station, network not loaded yet, no path). A real segment starts and ends on the
    /// stations' track nodes, so it's appended whole unless the line already ends exactly on its
    /// first point (the previous real segment ended there, or the caller anchored the stop on the
    /// same node) — dropping that point unconditionally would cut the corner off the track.
    static func polyline(
        through stops: [(signature: String, coordinate: CLLocationCoordinate2D)],
        route: (_ from: String, _ to: String) -> [CLLocationCoordinate2D]?
    ) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for (from, to) in zip(stops, stops.dropFirst()) {
            if let real = route(from.signature, to.signature), !real.isEmpty {
                let continues = result.last.map { $0.latitude == real[0].latitude && $0.longitude == real[0].longitude } ?? false
                result.append(contentsOf: continues ? real.dropFirst() : real[...])
            } else {
                if result.isEmpty {
                    result.append(from.coordinate)
                }
                result.append(to.coordinate)
            }
        }
        return result
    }
}

/// Minimal binary min-heap keyed by priority, just enough for Dijkstra over a ~7k node graph.
struct MinHeap<Element> {
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
