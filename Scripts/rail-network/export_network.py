import json
import pickle
import pyproj

to_wgs84 = pyproj.Transformer.from_crs("EPSG:3006", "EPSG:4326", always_xy=True)

with open("contracted_graph.pkl", "rb") as f:
    g = pickle.load(f)
with open("snapped_stations.json") as f:
    snapped = json.load(f)

node_list = list(g.nodes)
node_index = {n: i for i, n in enumerate(node_list)}


def to_ll(x, y):
    lon, lat = to_wgs84.transform(x, y)
    return [round(lat, 5), round(lon, 5)]


nodes_out = [to_ll(*n) for n in node_list]

edges_out = []
for u, v, data in g.edges(data=True):
    chain = data["chain"]
    if chain[0] != u:
        chain = list(reversed(chain))
    # store only the interior points (endpoints are implied by node indices) to avoid duplication
    interior = [to_ll(*p) for p in chain[1:-1]]
    edges_out.append([node_index[u], node_index[v], interior])

stations_out = {}
skipped = 0
for sig, v in snapped.items():
    node = tuple(v["node"])
    if node not in node_index:
        skipped += 1
        continue
    stations_out[sig] = node_index[node]

print(f"Nodes: {len(nodes_out)}, Edges: {len(edges_out)}, Stations: {len(stations_out)} (skipped {skipped})")

out = {"nodes": nodes_out, "edges": edges_out, "stations": stations_out}
with open("RailNetwork.json", "w", encoding="utf-8") as f:
    json.dump(out, f, separators=(",", ":"))

import os
size = os.path.getsize("RailNetwork.json")
print(f"RailNetwork.json size: {size / 1024:.0f} KB")
