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

    /// The real-track path between two stations, or `nil` if either signature isn't in the
    /// network, they're the same station, or no path connects them.
    func route(from: String, to: String) -> [CLLocationCoordinate2D]? {
        guard let start = stationNode[from], let goal = stationNode[to], start != goal else { return nil }
        return shortestPath(from: start, to: goal)
    }

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
