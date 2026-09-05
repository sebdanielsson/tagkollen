import sqlite3
import struct
import networkx as nx
from shapely import wkb as shapely_wkb
from shapely.geometry import LineString, MultiLineString

GPKG = "railnet/Järnvägsnät_grundegenskaper3_0_GeoPackage.gpkg"
TABLE = "Järnvägsnät_med_grundegenskaper3_0"


def gpkg_geom_to_wkb(blob):
    # GeoPackage binary header: 'GP' + version(1) + flags(1) + srs_id(int32) + envelope + WKB
    flags = blob[3]
    envelope_indicator = (flags >> 1) & 0x07
    envelope_len = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[envelope_indicator]
    header_len = 8 + envelope_len
    return blob[header_len:]


def snap(x, y):
    return (round(x, 1), round(y, 1))


def load_lines():
    con = sqlite3.connect(GPKG)
    cur = con.cursor()
    cur.execute(
        f"""SELECT id, geom, Pl_Forb, PlNamn, Straknamn, Bandel FROM '{TABLE}'
            WHERE Status = 'Öppen' AND SpTyp IN ('nhsp', 'ahsp', 'tågspår')"""
    )
    lines = []
    for row in cur.fetchall():
        rid, blob, pl_forb, pl_namn, straknamn, bandel = row
        if blob is None:
            continue
        try:
            geom = shapely_wkb.loads(gpkg_geom_to_wkb(blob))
        except Exception:
            continue
        if isinstance(geom, LineString):
            geoms = [geom]
        elif isinstance(geom, MultiLineString):
            geoms = list(geom.geoms)
        else:
            continue
        for g in geoms:
            if len(g.coords) >= 2:
                lines.append((rid, list(g.coords), pl_forb, pl_namn, straknamn, bandel))
    return lines


def build_graph(lines):
    g = nx.Graph()
    for rid, coords, pl_forb, pl_namn, straknamn, bandel in lines:
        for i in range(len(coords) - 1):
            a = snap(*coords[i])
            b = snap(*coords[i + 1])
            if a == b:
                continue
            dx = a[0] - b[0]
            dy = a[1] - b[1]
            dist = (dx * dx + dy * dy) ** 0.5
            if g.has_edge(a, b):
                if g[a][b]["weight"] <= dist:
                    continue
            g.add_edge(a, b, weight=dist)
    return g


if __name__ == "__main__":
    lines = load_lines()
    print(f"Loaded {len(lines)} line segments")
    graph = build_graph(lines)
    print(f"Graph: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges")
    components = list(nx.connected_components(graph))
    components.sort(key=len, reverse=True)
    print(f"Connected components: {len(components)}")
    print("Top 5 component sizes:", [len(c) for c in components[:5]])
