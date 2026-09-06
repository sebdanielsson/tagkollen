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
(free, CC0, just needs an email registration; the pipeline doesn't script the download, so
fetch the `.zip` from the portal by hand — Lastkajen does have a token-based API if that ever
needs automating). It ships ~195k short track segments (tens of metres
each) in SWEREF99TM, tagged with attributes like track type and status but no direct link to
Trafikverket's station signatures.

## Pipeline (`Scripts/rail-network/`)

Everything runs from inside `Scripts/rail-network/` and reads/writes files next to the scripts
(all of them git-ignored except the final copy under `Tagkollen/Resources/`):

```bash
cd Scripts/rail-network
pip install -r requirements.txt   # shapely, pyproj, networkx — no GDAL needed
```

Two inputs have to be in place first:

- `railnet/Järnvägsnät_grundegenskaper3_0_GeoPackage.gpkg` — the NJDB download from Lastkajen,
  unzipped. `build_graph.py` names the file and its table (`Järnvägsnät_med_grundegenskaper3_0`)
  explicitly; adjust `GPKG`/`TABLE` there if a newer release changes them.
- `stations.json` — the raw Open API response for every advertised station, saved as-is
  (`snap_stations.py` reads `RESPONSE.RESULT[0].TrainStation`). Any API key works:

  ```bash
  curl -s -X POST https://api.trafikinfo.trafikverket.se/v2/data.json -H 'Content-Type: text/xml' \
    -d "<REQUEST><LOGIN authenticationkey='$TRV_API_KEY'/><QUERY objecttype='TrainStation' namespace='rail.infrastructure' schemaversion='1.5'><FILTER><EQ name='Advertised' value='true'/></FILTER><INCLUDE>LocationSignature</INCLUDE><INCLUDE>AdvertisedLocationName</INCLUDE><INCLUDE>Geometry.WGS84</INCLUDE></QUERY></REQUEST>" \
    -o stations.json
  ```

1. **`build_graph.py`** — reads the GeoPackage straight out of SQLite (a GeoPackage is just
   SQLite; geometries are WKB with a small header we strip), keeping only open main-running
   track (`Status = 'Öppen'`, `SpTyp` in `nhsp`/`ahsp`/`tågspår` — excludes sidings and yard
   tracks). Builds an undirected graph: every vertex of every segment becomes a node (snapped to
   10cm to merge coincident points), consecutive vertices become weighted edges.
2. **`snap_stations.py`** — snaps every station in `stations.json` to the nearest graph node
   within 500 m (grid-indexed for speed). ~600/718 stations match — half of them within 15 m,
   nine in ten within 80 m, the worst just under 400 m where the directory coordinate is the
   station building rather than the platforms (Stockholm City, whose platforms are deep under
   the entrance, is ~320 m). The rest are foreign stations (`At.`/`De.`/`Dk.`…
   prefixes) not covered by the Swedish network at all, plus a couple of dozen Swedish ones:
   museum lines, harbour tracks and closed lines outside the open main-running track kept in
   step 1, and a couple of stops on long straight runs (Blattnicksele, Vattnäs) where the kept
   track passes right by but its nearest survey vertex is further away than the snap limit. All of
   them just fall back to a straight line in the app.
3. **`contract_graph.py`** — the raw graph has ~400k nodes, almost all of them degree-2 points
   that just sit along a straight-ish run between real junctions. It collapses every such chain
   into a single edge carrying the full sub-polyline, *pinning* every snapped station as a kept
   node first so no station disappears into a collapsed chain. Then simplifies each chain's
   polyline with Douglas-Peucker (15m tolerance). Result: ~6.9k nodes / ~9.1k edges, ~29k
   distinct coordinates (~40k polyline vertices counting each edge's shared endpoints) for the
   whole country.
4. **`export_network.py`** — converts back to WGS84, rounds to 5 decimals (~1m), and writes the
   final `RailNetwork.json` (~750KB): `nodes` (`[lat, lon]` per graph node), `edges` (one
   `[a, b, interior, length]` per contracted chain — node indices, the simplified interior
   points, and the exact pre-simplification track length in metres so the app never has to
   measure polylines itself) and `stations` (signature → node index).

Sanity check baked into `export_network.py`: it runs a shortest path Stockholm C → Mora C on the
exact graph being exported and refuses to write the file if the result strays more than 5 km
from the real-world 329.6 km, so a dropped line or a broken contraction can't ship silently.

## On the app side

- `RailGraph` is the pure data structure (nodes, edges, adjacency, station lookup) plus Dijkstra
  between two station signatures. Each edge's polyline is stored once; the adjacency entry says
  which direction to walk it. It's tested against a small synthetic graph in `RailGraphTests`.
- `RailNetwork` owns loading and caching: `AppDependencies.start()` calls `preload()` at launch,
  which parses the JSON off the main actor. `route(from:to:)` returns `nil` until that finishes
  and memoises every answer (including misses) per station pair.
- `TrainMapView` computes the selected journey's polyline once per selection (not in `body`) by
  concatenating the real path between each consecutive pair of its stops — there's no precomputed
  table of "every travelled station pair" — and falls back to a straight segment for any pair
  where either station isn't in the network or the network hasn't loaded yet.

## Regenerating

Needed only if NJDB publishes a materially different network (new lines, major reroutes) — the
existing file doesn't need routine updates. Expect the station count to move a little when you
do: the shipped file was produced before `snap_stations.py`'s grid scan was widened to cover the
full 500 m limit, so a regeneration may pick up a handful of stations the old scan missed
(Hackås, whose nearest track vertex is ~340 m away, is one). Re-download the GeoPackage from Lastkajen and refresh
`stations.json` as described above, then:

```bash
cd Scripts/rail-network
python3 build_graph.py && python3 snap_stations.py && python3 contract_graph.py && python3 export_network.py
cp RailNetwork.json ../../Tagkollen/Resources/RailNetwork.json
```
