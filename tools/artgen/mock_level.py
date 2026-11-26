"""Builds a playable level from a free-form layout (polygons, roads, rivers) set in map_compare.py.

tiled_import.py fills the layout from a Tiled map and calls build(); MOCK_META describes
the hand-drawn example (tools/maps/example.tmj).
Run the game on it with:  -- --level=<name>   (or pick "Try: <name>" on the title screen in debug builds)
"""
import json, math, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import map_compare as M

PX = 2.0   # same density as the real ground (TEX 0.5)
WM = 1.0   # walk mask: 1 pixel per world unit


def circle(poly):
    """Centre and a radius that fits the shape (encounter trigger for a clearing)."""
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    area = 0.5 * abs(sum(xs[i] * ys[i - 1] - xs[i - 1] * ys[i] for i in range(len(poly))))
    return [round(cx), round(cy)], round(math.sqrt(area / math.pi) * 0.95)


def _seg_x(p1, p2, q1, q2):
    """Intersection point of segments p1p2 and q1q2, or None."""
    (x1, y1), (x2, y2), (x3, y3), (x4, y4) = p1, p2, q1, q2
    d = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(d) < 1e-9:
        return None
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
    u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / d
    if 0 <= t <= 1 and 0 <= u <= 1:
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
    return None


def seals_for(areas):
    """Thorn barriers where roads cross the edge of each sealed area."""
    out = {}
    for a in areas:
        if not a.get("seal") or not a["encounter"]:
            continue
        poly = M.CLEARINGS[a["id"]]
        lst = []
        for pts, hw in M.ROADS:
            pts = list(pts)
            # a road that stops at the edge still enters: stretch its ends a little
            for e, o in ((0, 1), (len(pts) - 1, len(pts) - 2)):
                (ex, ey), (ox, oy) = pts[e], pts[o]
                L = math.hypot(ex - ox, ey - oy) or 1.0
                pts[e] = (ex + (ex - ox) / L * hw * 1.5, ey + (ey - oy) / L * hw * 1.5)
            for i in range(len(pts) - 1):
                for j in range(len(poly)):
                    x = _seg_x(pts[i], pts[i + 1], poly[j], poly[(j + 1) % len(poly)])
                    if x:
                        lst.append({"pos": [round(x[0]), round(x[1])], "r": round(hw * 1.75 + 6)})
        out[a["id"]] = lst
    return out


def build(name, art, assets, meta, extra_props=(), preview=None, level_file=None):
    """meta: {"title", "areas": {id: {name, encounter, boss, seal}}, "shrine", "campfire", "gate", "route"}"""
    g, sd, water, walk = M.paint(PX, art)
    rgb = np.asarray(g.convert("RGB"))
    Image.fromarray(rgb).save(os.path.join(assets, "ground_%s.png" % name))
    # normals from luminance, like the real ground
    lum = ndimage.gaussian_filter(rgb.mean(-1, dtype=np.float32), 1.2) / np.float32(255.0)
    nimg = np.empty(rgb.shape, np.uint8)
    for y0 in range(0, lum.shape[0], 512):   # in bands: big maps
        y1 = min(lum.shape[0], y0 + 512)
        a0, a1 = max(0, y0 - 1), min(lum.shape[0], y1 + 1)
        gy, gx = np.gradient(lum[a0:a1])
        gy, gx = gy[y0 - a0:y0 - a0 + (y1 - y0)], gx[y0 - a0:y0 - a0 + (y1 - y0)]
        nx, ny = -gx * 6, -gy * 6
        n = np.sqrt(nx * nx + ny * ny + 1.0)
        nimg[y0:y1] = (np.stack([nx / n, ny / n, 1.0 / n], -1) * 127.5 + 127.5).astype(np.uint8)
    Image.fromarray(nimg).save(os.path.join(assets, "ground_%s_n.png" % name))
    spec = np.clip(water * 200 + 30, 0, 255).astype(np.uint8)
    Image.fromarray(np.stack([spec] * 3, -1)).save(os.path.join(assets, "ground_%s_s.png" % name))

    # walkability: rivers block except at bridges and fords
    w1, _, wat1 = M.raster_mask(WM)
    ok = w1 & ~wat1
    yy, xx = np.mgrid[0:ok.shape[0], 0:ok.shape[1]]
    for (cx, cy), kind in M.CROSSINGS:
        (ux, uy), half, wide = M.crossing_frame(cx, cy)
        across = (xx - cx) * ux + (yy - cy) * uy
        along = (xx - cx) * -uy + (yy - cy) * ux
        ok |= (np.abs(across) < half + 6) & (np.abs(along) < wide)
    Image.fromarray((ok * 255).astype(np.uint8)).save(os.path.join(assets, "walkmask_%s.png" % name))

    areas = []
    for cid, poly in M.CLEARINGS.items():
        info = meta["areas"].get(cid, {})
        pos, r = circle(poly)
        a = {"id": cid, "name": info.get("name", cid.replace("_", " ").title()), "pos": pos, "r": r,
             "encounter": list(info.get("encounter", []))}
        if info.get("boss"):
            a["boss"] = True
        if info.get("seal"):
            a["seal"] = True
        if info.get("final"):
            a["final"] = True
        if info.get("bossinfo"):
            a["bossinfo"] = info["bossinfo"]
        areas.append(a)
    props = M.mock_props(sd, water, PX) + list(extra_props)
    solids = [{"pos": [round(p["pos"][0]), round(p["pos"][1])], "r": 12} for p in props
              if p["name"].startswith(("ruin_wall", "rock_0", "standing_stone", "gibbet"))]
    # set pieces that stand on walkable ground block it, so what looks solid is solid
    SOLID_R = {"cem_angel_s": 9, "cem_angel": 15, "cem_cross": 6, "cem_stone": 9, "cem_column": 6, "ud_rock_0": 11, "ud_rock_1": 9,
               "ud_ruin_0": 16, "ud_ruin_1": 16, "ud_ruin_2": 9, "ud_deadtree": 8, "ud_tree_0": 10, "ud_skulls": 12, "ud_crystal_0": 8}
    hh, ww = sd.shape
    for p in props:
        for pre, r in SOLID_R.items():
            if p["name"].startswith(pre):
                ix = int(min(ww - 1, max(0, p["pos"][0] * PX)))
                iy = int(min(hh - 1, max(0, p["pos"][1] * PX)))
                if sd[iy, ix] > -6:
                    solids.append({"pos": [round(p["pos"][0]), round(p["pos"][1])], "r": r})
                break
    for p in props:
        p["pos"] = [round(p["pos"][0]), round(p["pos"][1])]
        if p["name"].startswith("brazier_"):
            p["name"] = "brazier"       # the game animates and lights these
    # a solid only matters where you could walk into it
    def _near_walk(q):
        ix = int(min(ww - 1, max(0, q["pos"][0] * PX)))
        iy = int(min(hh - 1, max(0, q["pos"][1] * PX)))
        return sd[iy, ix] > -(q["r"] + 4)
    solids = [q for q in solids if _near_walk(q)]
    for key, prop in (("shrine", "moth_shrine"), ("campfire", "campfire")):
        if meta.get(key):
            props.append({"name": prop, "pos": list(meta[key])})
            solids.append({"pos": list(meta[key]), "r": 12})
    gate = meta.get("gate") or {"pos": [-999, -999], "r": 1}
    L = {
        "title": meta.get("title", name.upper()), "ground": "ground_%s" % name, "walkmask": "walkmask_%s" % name,
        "walkmask_scale": WM, "size": [M.W, M.H], "tex": 1.0 / PX, "areas": areas, "paths": [],
        "gate": gate, "shrine": list(meta["shrine"]), "campfire": list(meta.get("campfire") or meta["shrine"]),
        "route": meta.get("route") or [a["pos"] for a in areas], "props": props, "solids": solids, "torches": [], "seals": seals_for(areas),
        "glows": [[round(x), round(y), kind] for x, y, kind in M.GLOWS],
    }
    for key in ("act", "subtitle", "night", "weather", "gate_after", "prop_tint", "exit", "rift"):
        if meta.get(key) is not None:
            L[key] = meta[key]
    if meta.get("weather") == "ash":
        L["ash"] = True
    json.dump(L, open(os.path.join(assets, level_file or "level_%s.json" % name), "w"))
    if preview:
        # a 1 px per world unit picture of the result, to draw over in Tiled next time
        Image.fromarray(rgb).resize((M.W, M.H), Image.LANCZOS).save(preview)
    print("level %s: props %d, areas %s" % (name, len(props), [(a["id"], a["r"]) for a in areas]))
    return L


MOCK_META = {
    "title": "PROTOTYPE: HAND-DRAWN LAYOUT",
    "areas": {
        "camp": {"name": "Camp & Shrine"},
        "crossroads": {"name": "Gallows Crossroads", "encounter": ["ghoul"] * 5 + ["cultist"]},
        "hermit": {"name": "Hermit's Hollow", "encounter": ["ghoul", "ghoul"]},
        "quarry": {"name": "Brute Quarry", "encounter": ["brute", "brute", "ghoul", "ghoul", "cultist"]},
        "village": {"name": "The Drowned Village", "encounter": ["ghoul", "ghoul", "cultist", "cultist", "ghoul", "ghoul", "cultist"]},
        "pit": {"name": "The Iron Brother's Pit", "encounter": ["iron_brother", "cultist", "cultist", "ghoul", "ghoul"], "boss": True, "seal": True},
    },
    "shrine": [350, 1250], "campfire": [420, 1330],
    "gate": {"pos": [1840, 700], "r": 34, "open_from": [0, -1]},
    "route": [[380, 1300], [620, 1240], [950, 1140], [1290, 1110], [1780, 1150], [1840, 800], [1900, 450]],
}

if __name__ == "__main__":
    print("Build levels with tiled_import.py (--example writes this layout as a Tiled map).")
