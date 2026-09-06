import json
import math

import pyproj
from build_graph import load_lines, build_graph

transformer = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:3006", always_xy=True)

with open("stations.json", encoding="utf-8") as f:
    data = json.load(f)
stations = data["RESPONSE"]["RESULT"][0]["TrainStation"]


def parse_point(wkt):
    # "POINT (lon lat)"
    inner = wkt[wkt.index("(") + 1 : wkt.index(")")]
    lon, lat = map(float, inner.split())
    return lon, lat


if __name__ == "__main__":
    lines = load_lines()
    graph = build_graph(lines)
    print(f"Graph: {graph.number_of_nodes()} nodes")

    # Spatial grid index for nearest-node lookup (avoid O(n*m) brute force over 400k nodes x 718 stations)
    from collections import defaultdict

    # Stations further than `max_snap` from any open main-running track (harbours, museum lines,
    # closed stations) are deliberately left out rather than glued onto an unrelated line; the app
    # draws straight lines for them. Within the limit the offset is real: a directory coordinate is
    # often the station building, while the node is on the platform track (Stockholm City ~320 m).
    max_snap = 500.0  # meters
    cell_size = 200.0  # meters
    # Enough neighbouring cells that every node within `max_snap` of a query is seen, whatever the
    # query's position inside its own cell.
    cell_reach = math.ceil(max_snap / cell_size)
    grid = defaultdict(list)
    for node in graph.nodes:
        cx, cy = int(node[0] // cell_size), int(node[1] // cell_size)
        grid[(cx, cy)].append(node)

    def nearest_node(x, y, max_dist=max_snap):
        cx, cy = int(x // cell_size), int(y // cell_size)
        best, best_d = None, max_dist
        for dcx in range(-cell_reach, cell_reach + 1):
            for dcy in range(-cell_reach, cell_reach + 1):
                for node in grid.get((cx + dcx, cy + dcy), []):
                    d = ((node[0] - x) ** 2 + (node[1] - y) ** 2) ** 0.5
                    if d < best_d:
                        best, best_d = node, d
        return best, best_d

    snapped = {}
    unmatched = []
    for st in stations:
        geom = st.get("Geometry", {}).get("WGS84")
        if not geom:
            unmatched.append((st["LocationSignature"], "no coordinate"))
            continue
        lon, lat = parse_point(geom)
        x, y = transformer.transform(lon, lat)
        node, dist = nearest_node(x, y)
        if node is None:
            unmatched.append((st["LocationSignature"], f"no node within {max_snap:.0f}m"))
            continue
        snapped[st["LocationSignature"]] = {"node": node, "dist": round(dist, 1), "name": st["AdvertisedLocationName"]}

    print(f"Snapped {len(snapped)} / {len(stations)} stations")
    print(f"Unmatched: {len(unmatched)}")
    for sig, reason in unmatched[:30]:
        print(" ", sig, reason)

    dists = sorted(v["dist"] for v in snapped.values())
    print("Snap distance percentiles (m): p50=%.1f p90=%.1f p99=%.1f max=%.1f" % (
        dists[len(dists) // 2], dists[int(len(dists) * 0.9)], dists[int(len(dists) * 0.99)], dists[-1]
    ))

    with open("snapped_stations.json", "w", encoding="utf-8") as f:
        json.dump({sig: {"node": list(v["node"]), "dist": v["dist"], "name": v["name"]} for sig, v in snapped.items()}, f)
