# Rail network geometry

`Tagkollen/Resources/RailNetwork.json` lets the map draw a train's route following the real
shape of the track instead of straight lines between stations (`RailNetwork.swift`). It's
generated offline from Trafikverket's National Railway Database (NJDB) and checked in as a
static bundled resource — nothing about it is fetched at runtime.

## Where the data comes from

The Trafikverket Open API used everywhere else in the app (`TrainPosition`, `TrainAnnouncement`,
`TrainStation`, …) has no track geometry — only points. The actual rail network shape is a
separate product, **"Järnvägsnät med grundegenskaper"**, distributed as a GeoPackage through
[Lastkajen](https://www.trafikverket.se/e-tjanster/lastkajen--sveriges-vag--och-jarnvagsdata/)
(free, CC0, just needs an email registration — there's no API key or scripted download, a human
has to fetch the `.zip` from the portal). It ships ~195k tiny track segments (a few meters each)
in SWEREF99TM, tagged with attributes like track type and status but no direct link to
Trafikverket's station signatures.

## Pipeline (`Scripts/rail-network/`)

```
pip install -r Scripts/rail-network/requirements.txt   # shapely, pyproj, networkx — no GDAL needed
```

1. **`build_graph.py`** — reads the GeoPackage straight out of SQLite (a GeoPackage is just
   SQLite; geometries are WKB with a small header we strip), keeping only open main-running
   track (`Status = 'Öppen'`, `SpTyp` in `nhsp`/`ahsp`/`tågspår` — excludes sidings and yard
   tracks). Builds an undirected graph: segment endpoints become nodes (snapped to 10cm to merge
   coincident points), segments become weighted edges.
2. **`snap_stations.py`** — fetches every advertised `TrainStation` from the live API and snaps
   each to its nearest graph node (grid-indexed for speed). ~600/718 stations match within a few
   metres; the rest are foreign border stations (`At.`/`De.`/`Dk.` prefixes) not covered by the
   Swedish network at all — expected, they just fall back to a straight line in the app.
3. **`contract_graph.py`** — the raw graph has ~400k nodes, almost all of them degree-2 points
   that just sit along a straight-ish run between real junctions. It collapses every such chain
   into a single edge carrying the full sub-polyline, *pinning* every snapped station as a kept
   node first so no station disappears into a collapsed chain. Then simplifies each chain's
   polyline with Douglas-Peucker (15m tolerance). Result: ~6.9k nodes / ~9.1k edges, ~40k total
   coordinate points for the whole country.
4. **`export_network.py`** — converts back to WGS84, rounds to 5 decimals (~1m), and writes the
   final `RailNetwork.json` (`{nodes, edges, stations}`, ~700KB).

Sanity check baked into the pipeline: Stockholm C → Mora C resolves to 329.6km, matching the
real-world rail distance, computed in single-digit milliseconds even before contraction.

## On the app side

`RailNetwork.swift` loads the bundled JSON once, builds an adjacency list, and runs Dijkstra
between two station signatures on demand — there's no precomputed table of "every travelled
station pair"; a journey's route is just the concatenation of the real path between each
consecutive pair of its actual stops; `TrainMapView.routePolyline(for:)` falls back to a straight
segment for any pair where either station isn't in the network.

## Regenerating

Needed only if NJDB publishes a materially different network (new lines, major reroutes) — the
existing file doesn't need routine updates. Re-download the GeoPackage from Lastkajen, drop it in
as `Scripts/rail-network/railnet/*.gpkg`, and rerun the four scripts in order (each writes its
output next to itself; `export_network.py`'s `RailNetwork.json` goes to
`Tagkollen/Resources/RailNetwork.json`).
