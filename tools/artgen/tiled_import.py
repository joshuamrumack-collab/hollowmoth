"""Tiled -> Hollowmoth level.

Draw a level in Tiled (https://www.mapeditor.org, free) as object layers, then:
    python tools/artgen/tiled_import.py tools/maps/<map>.tmj [level name] [--art Art]
It paints the ground, places forest and dressing, writes the walk mask and
assets/level_<name>.json. Play it with "Try: <name>" on the title screen (debug
builds) or run the game with  -- --level=<name>.

Layers (object layers, names matter; 1 Tiled pixel = 1 world unit):
  clearings  polygons / rectangles / ellipses = walkable areas. The object's Name is the
             area id. Custom properties (all optional):
               title    string   name shown on entering ("The Drowned Village")
               enemies  string   comma list: ghoul, cultist, brute, iron_brother, ...
               boss     bool     a boss arena (music, banner, seals)
               seal     bool     the way closes behind you until the fight is won
               floor    string   flag (flagstones), bones, mud; default moss + mud
  roads      polylines = paths. Property width (float, default 70).
  water      polylines = rivers / streams, block walking. Property width (default 70).
  crossings  points or rectangles across water; Class = bridge or ford.
  markers    points named shrine, campfire, gate; optional polyline named route
             (the order the test bot walks). gate property open_from = "x,y" direction.
  props      points whose Class is a prop name (brazier, ruin_wall_0, gibbet, ...);
             placed exactly where you put them. The forest fills itself in.
  preview    (image layer, ignored) the painted result of the last import, to draw over.

Also: python tiled_import.py --example tools/maps/example.tmj
writes the hand-drawn test layout as a Tiled map to start from.
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import map_compare as M
import mock_level as B

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))


def props_of(o):
    out = {}
    for p in o.get("properties", []) or []:
        out[p["name"]] = p["value"]
    return out


def klass(o):
    return o.get("class") or o.get("type") or ""


def shape_points(o):
    """Any Tiled shape as a list of world points (polygons absolute; ellipses approximated)."""
    x, y = o["x"], o["y"]
    if "polygon" in o:
        return [(x + p["x"], y + p["y"]) for p in o["polygon"]]
    if "polyline" in o:
        return [(x + p["x"], y + p["y"]) for p in o["polyline"]]
    w, h = o.get("width", 0), o.get("height", 0)
    if o.get("ellipse"):
        cx, cy = x + w / 2, y + h / 2
        return [(cx + math.cos(t / 20 * math.tau) * w / 2, cy + math.sin(t / 20 * math.tau) * h / 2) for t in range(20)]
    if w and h:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    return [(x, y)]


def centre(o):
    pts = shape_points(o)
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def load(path):
    m = json.load(open(path))
    W = m["width"] * m["tilewidth"]
    H = m["height"] * m["tileheight"]
    layers = {l["name"].strip().lower(): l for l in m.get("layers", []) if l.get("type") == "objectgroup"}
    clearings, floors, meta_areas = {}, {}, {}
    for o in layers.get("clearings", {}).get("objects", []):
        cid = (o.get("name") or "area_%d" % o["id"]).strip().lower().replace(" ", "_")
        pr = props_of(o)
        clearings[cid] = shape_points(o)
        if pr.get("floor"):
            floors[cid] = pr["floor"]
        meta_areas[cid] = {"name": pr.get("title", cid.replace("_", " ").title()),
                           "encounter": [e.strip() for e in str(pr.get("enemies", "")).split(",") if e.strip()],
                           "boss": bool(pr.get("boss", False)), "seal": bool(pr.get("seal", False)),
                           "final": bool(pr.get("final", False))}
        bi = {k[5:]: pr[k] for k in pr if k.startswith("boss_")}
        bi.update({k: pr[k] for k in ("intro", "dead", "victory", "music") if k in pr})
        if bi:
            meta_areas[cid]["bossinfo"] = bi
    roads = [(shape_points(o), float(props_of(o).get("width", 70)) / 2) for o in layers.get("roads", {}).get("objects", []) if "polyline" in o]
    rivers = [(shape_points(o), float(props_of(o).get("width", 70)) / 2) for o in layers.get("water", {}).get("objects", []) if "polyline" in o]
    crossings = [(centre(o), (klass(o) or "bridge").lower()) for o in layers.get("crossings", {}).get("objects", [])]
    marks = {}
    route = None
    for o in layers.get("markers", {}).get("objects", []):
        n = (o.get("name") or "").strip().lower()
        if n == "route" and "polyline" in o:
            route = [[round(x), round(y)] for x, y in shape_points(o)]
        elif n:
            marks[n] = (o, [round(v) for v in centre(o)])
    extra = [{"name": klass(o), "pos": list(centre(o))} for o in layers.get("props", {}).get("objects", []) if klass(o)]
    mp = props_of(m)
    meta = {"title": mp.get("title", os.path.splitext(os.path.basename(path))[0].replace("_", " ").upper()),
            "areas": meta_areas, "route": route, "act": int(mp["act"]) if "act" in mp else None,
            "subtitle": mp.get("subtitle"), "weather": mp.get("weather"), "gate_after": mp.get("gate_after"),
            "palette": mp.get("palette", "forest"), "water": mp.get("water", "river")}
    for key in ("night", "prop_tint"):
        if key in mp:
            meta[key] = [float(v) for v in str(mp[key]).split(",")]
    for key in ("exit", "rift"):
        if key in marks:
            meta[key] = marks[key][1]
    if "shrine" in marks:
        meta["shrine"] = marks["shrine"][1]
    elif clearings:
        meta["shrine"] = [round(v) for v in centre({"x": 0, "y": 0, "polygon": [{"x": p[0], "y": p[1]} for p in next(iter(clearings.values()))]})]
    if "campfire" in marks:
        meta["campfire"] = marks["campfire"][1]
    if "gate" in marks:
        go = props_of(marks["gate"][0]).get("open_from", "0,-1")
        meta["gate"] = {"pos": marks["gate"][1], "r": 34, "open_from": [float(v) for v in str(go).split(",")]}
    return W, H, clearings, floors, roads, rivers, crossings, meta, extra


def install(W, H, clearings, floors, roads, rivers, crossings, palette="forest", water="river"):
    """Point the painter (map_compare) at this layout."""
    M.W, M.H = W, H
    M.PALETTE, M.WATER = palette, water
    M.CLEARINGS = clearings
    M.FLOORS = floors
    M.ROADS = roads
    M.RIVERS = rivers
    M.CROSSINGS = crossings
    M.HOUSES = []
    M.DRESSING = {}


def write_map(path, W, H, map_props, clearings, roads, rivers, crossings, markers, props, route=None):
    """Write a Tiled map. clearings: {id: (polygon, {prop: value})}; roads/rivers: [(points, width)];
    crossings: [((x, y), kind)]; markers: {name: (x, y)}; props: [(name, (x, y))]."""
    oid = [1]

    def obj(name="", cls="", **kw):
        o = {"id": oid[0], "name": name, "type": cls, "rotation": 0, "visible": True, "x": 0, "y": 0, "width": 0, "height": 0}
        oid[0] += 1
        o.update(kw)
        return o

    def prop(n, v):
        t = "bool" if isinstance(v, bool) else "int" if isinstance(v, int) else "float" if isinstance(v, float) else "string"
        return {"name": n, "type": t, "value": v}

    def pts(seq):
        return [{"x": round(x), "y": round(y)} for x, y in seq]
    clear = [obj(cid, polygon=pts(poly), properties=[prop(k, v) for k, v in pr.items()]) for cid, (poly, pr) in clearings.items()]
    rds = [obj("road", polyline=pts(p), properties=[prop("width", float(w))]) for p, w in roads]
    wat = [obj("water", polyline=pts(p), properties=[prop("width", float(w))]) for p, w in rivers]
    crs = [obj(kind, kind, x=x, y=y, point=True) for (x, y), kind in crossings]
    mk = []
    for n, v in markers.items():
        if isinstance(v, dict):
            mk.append(obj(n, x=v["pos"][0], y=v["pos"][1], point=True, properties=[prop(k, val) for k, val in v.items() if k != "pos"]))
        else:
            mk.append(obj(n, x=v[0], y=v[1], point=True))
    if route:
        mk.append(obj("route", polyline=pts(route)))
    pr_ = [obj("", n, x=x, y=y, point=True) for n, (x, y) in props]
    preview = os.path.splitext(os.path.basename(path))[0] + "_preview.png"

    def layer(i, n, objs, color):
        return {"id": i, "name": n, "type": "objectgroup", "draworder": "topdown", "objects": objs,
                "opacity": 1, "visible": True, "x": 0, "y": 0, "color": color}
    TW = 16
    m = {
        "type": "map", "version": "1.10", "tiledversion": "1.11.0", "orientation": "orthogonal", "renderorder": "right-down",
        "width": -(-W // TW), "height": -(-H // TW), "tilewidth": TW, "tileheight": TW, "infinite": False,
        "nextlayerid": 10, "nextobjectid": oid[0] + 1, "tilesets": [],
        "properties": [prop(k, v) for k, v in map_props.items()],
        "layers": [
            {"id": 1, "name": "preview", "type": "imagelayer", "image": preview, "opacity": 0.7, "visible": True,
             "x": 0, "y": 0, "repeatx": False, "repeaty": False},
            layer(2, "clearings", clear, "#7fc97f"), layer(3, "roads", rds, "#c9a26b"), layer(4, "water", wat, "#4f8fd6"),
            layer(5, "crossings", crs, "#e0d070"), layer(6, "markers", mk, "#ff7070"), layer(7, "props", pr_, "#c080ff"),
        ],
    }
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    json.dump(m, open(path, "w"), indent=1)
    print("wrote", path)


def write_example(path):
    """The hand-drawn test layout as a Tiled map, to open and change."""
    oid = [1]

    def obj(name="", cls="", **kw):
        o = {"id": oid[0], "name": name, "type": cls, "rotation": 0, "visible": True, "x": 0, "y": 0, "width": 0, "height": 0}
        oid[0] += 1
        o.update(kw)
        return o

    def prop(n, t, v):
        return {"name": n, "type": t, "value": v}

    clear = []
    for cid, poly in M.CLEARINGS.items():
        info = B.MOCK_META["areas"].get(cid, {})
        pr = [prop("title", "string", info.get("name", cid))]
        if info.get("encounter"):
            pr.append(prop("enemies", "string", ", ".join(info["encounter"])))
        if info.get("boss"):
            pr.append(prop("boss", "bool", True))
        if info.get("seal"):
            pr.append(prop("seal", "bool", True))
        if cid in M.FLOORS:
            pr.append(prop("floor", "string", M.FLOORS[cid]))
        clear.append(obj(cid, x=0, y=0, polygon=[{"x": x, "y": y} for x, y in poly], properties=pr))
    roads = [obj("road", x=0, y=0, polyline=[{"x": x, "y": y} for x, y in pts], properties=[prop("width", "float", hw * 2)]) for pts, hw in M.ROADS]
    water = [obj("river", x=0, y=0, polyline=[{"x": x, "y": y} for x, y in pts], properties=[prop("width", "float", hw * 2)]) for pts, hw in M.RIVERS]
    cross = [obj(kind, kind, x=x, y=y, point=True) for (x, y), kind in M.CROSSINGS]
    mk = B.MOCK_META
    markers = [obj("shrine", x=mk["shrine"][0], y=mk["shrine"][1], point=True),
               obj("campfire", x=mk["campfire"][0], y=mk["campfire"][1], point=True),
               obj("gate", x=mk["gate"]["pos"][0], y=mk["gate"]["pos"][1], point=True, properties=[prop("open_from", "string", "0,-1")]),
               obj("route", x=0, y=0, polyline=[{"x": x, "y": y} for x, y in mk["route"]])]
    props = []
    for hx, hy in M.HOUSES:
        for k in range(2):
            props.append(obj("", "ruin_wall_%d" % k, x=hx + k * 34 - 17, y=hy, point=True))
    preview = os.path.splitext(os.path.basename(path))[0] + "_preview.png"

    def layer(n, objs, color):
        return {"id": oid[0] + 1000 + len(n), "name": n, "type": "objectgroup", "draworder": "topdown", "objects": objs,
                "opacity": 1, "visible": True, "x": 0, "y": 0, "color": color}
    TW = 16
    m = {
        "type": "map", "version": "1.10", "tiledversion": "1.11.0", "orientation": "orthogonal", "renderorder": "right-down",
        "width": M.W // TW, "height": -(-M.H // TW), "tilewidth": TW, "tileheight": TW, "infinite": False,
        "nextlayerid": 20, "nextobjectid": oid[0] + 1, "tilesets": [],
        "properties": [prop("title", "string", "HAND-DRAWN EXAMPLE")],
        "layers": [
            {"id": 1, "name": "preview", "type": "imagelayer", "image": preview, "opacity": 0.7, "visible": True,
             "x": 0, "y": 0, "repeatx": False, "repeaty": False},
            layer("clearings", clear, "#7fc97f"), layer("roads", roads, "#c9a26b"), layer("water", water, "#4f8fd6"),
            layer("crossings", cross, "#e0d070"), layer("markers", markers, "#ff7070"), layer("props", props, "#c080ff"),
        ],
    }
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    json.dump(m, open(path, "w"), indent=1)
    print("wrote", path)
    return os.path.join(os.path.dirname(path), preview)


def main():
    args = [a for a in sys.argv[1:]]
    art = os.path.join(PROJECT, "tools", "maps", "textures")   # mud, moss, flag, bones (from the ground art)
    if "--art" in args:
        i = args.index("--art")
        art = args[i + 1]
        del args[i:i + 2]
    assets = os.path.join(PROJECT, "assets")
    if args and args[0] == "--example":
        out = args[1] if len(args) > 1 else os.path.join(PROJECT, "tools", "maps", "example.tmj")
        preview = write_example(out)
        B.build("example", art, assets, {**B.MOCK_META, "title": "HAND-DRAWN EXAMPLE"}, preview=preview)
        return
    path = args[0]
    name = args[1] if len(args) > 1 else os.path.splitext(os.path.basename(path))[0].lower().replace(" ", "_")
    W, H, clearings, floors, roads, rivers, crossings, meta, extra = load(path)
    if not clearings:
        sys.exit("No polygons on a 'clearings' layer: nothing to walk on.")
    if not meta.get("shrine"):
        sys.exit("Put a point named 'shrine' on the 'markers' layer.")
    install(W, H, clearings, floors, roads, rivers, crossings, meta["palette"], meta["water"])
    preview = os.path.join(os.path.dirname(path), os.path.splitext(os.path.basename(path))[0] + "_preview.png")
    act = meta.get("act")
    if act:
        # an act map replaces that act's level: level.json (Act I) or level_<n>.json
        name = "act%d" % act
        lf = "level.json" if act == 1 else "level_%d.json" % act
        B.build(name, art, assets, meta, extra, preview=preview, level_file=lf)
        # the walk-here overlay (tools/artgen/edge_overlay.py)
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import edge_overlay
        edge_overlay.build(os.path.join(assets, lf))
    else:
        B.build(name, art, assets, meta, extra, preview=preview)


if __name__ == "__main__":
    main()
