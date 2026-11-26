"""Builds Act I 'The Hollowmarch Outskirts': ground art (PNG) + layout (JSON).

Areas are circles joined by paths (capsules). Everything outside is dense
pine forest. The JSON is the single source of truth Godot reads for
walkability, encounters, seals, the shortcut gate and every prop.
"""
import json, math, os, random
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "out")
W, H = 1600, 1100
TEX = 0.5   # world px per ground texel (2x density, shown at scale 0.5)

AREAS = [
    {"id": "camp", "name": "Moth Shrine Camp", "pos": [300, 820], "r": 115, "encounter": []},
    {"id": "glade", "name": "The Gallows Glade", "pos": [640, 640], "r": 135,
     "encounter": ["ghoul", "ghoul", "ghoul", "ghoul", "ghoul", "ghoul", "cultist"]},
    {"id": "chapel", "name": "The Drowned Chapel", "pos": [1080, 720], "r": 145, "seal": True,
     "encounter": ["ghoul", "ghoul", "ghoul", "cultist", "cultist", "ghoul", "ghoul"]},
    {"id": "hollow", "name": "Brute Hollow", "pos": [1180, 330], "r": 135,
     "encounter": ["brute", "brute", "ghoul", "ghoul", "ghoul", "cultist", "cultist"]},
    {"id": "pit", "name": "The Iron Brother's Pit", "pos": [690, 250], "r": 165, "boss": True, "seal": True,
     "encounter": ["iron_brother", "cultist", "cultist", "ghoul", "ghoul"]},
]
PATHS = [
    {"a": [300, 820], "b": [640, 640], "hw": 34},
    {"a": [640, 640], "b": [1080, 720], "hw": 34},
    {"a": [1080, 720], "b": [1180, 330], "hw": 34},
    {"a": [1180, 330], "b": [690, 250], "hw": 36},
    # shortcut: chapel back to camp along the south, through an iron gate
    {"a": [1080, 720], "b": [760, 960], "hw": 28},
    {"a": [760, 960], "b": [300, 820], "hw": 28},
]
GATE = {"pos": [540, 890], "r": 30}
SHRINE = [282, 770]
CAMPFIRE = [322, 838]
ROUTE = [[300, 820], [470, 730], [640, 640], [860, 680], [1080, 720], [1130, 520], [1180, 330], [940, 290], [690, 250]]

# The layout above was drawn at 1x; the act is built bigger so fights have room to move.
S = 1.5
PATH_S = 1.25


def scale_layout(g, s, path_s):
    """Scale every position in a layout module's globals (dict g) by s."""
    sp = lambda p: [round(p[0] * s), round(p[1] * s)]
    g["W"], g["H"] = round(g["W"] * s), round(g["H"] * s)
    for a in g["AREAS"]:
        a["pos"] = sp(a["pos"]); a["r"] = round(a["r"] * s)
    for p in g["PATHS"]:
        p["a"] = sp(p["a"]); p["b"] = sp(p["b"]); p["hw"] = round(p["hw"] * path_s)
    g["GATE"]["pos"] = sp(g["GATE"]["pos"])
    g["GATE"]["r"] = round(g["GATE"]["r"] * path_s)
    for k in ("SHRINE", "CAMPFIRE", "RIFT"):
        if k in g:
            g[k] = sp(g[k])
    g["ROUTE"] = [sp(p) for p in g["ROUTE"]]


scale_layout(globals(), S, PATH_S)


def seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def walk_field():
    """Signed-ish field: >0 inside walkable (distance into it), plus path mask."""
    ys, xs = np.mgrid[0:H:TEX, 0:W:TEX].astype(np.float32) + TEX / 2
    inside = np.full(xs.shape, -999.0, np.float32)
    path = np.full(xs.shape, -999.0, np.float32)
    for a in AREAS:
        d = a["r"] - np.hypot(xs - a["pos"][0], ys - a["pos"][1])
        inside = np.maximum(inside, d)
    for p in PATHS:
        ax, ay = p["a"]; bx, by = p["b"]
        dx, dy = bx - ax, by - ay
        t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / (dx * dx + dy * dy), 0, 1)
        d = p["hw"] - np.hypot(xs - (ax + t * dx), ys - (ay + t * dy))
        inside = np.maximum(inside, d)
        path = np.maximum(path, d)
    return xs, ys, inside, path


def value_noise(shape, scale, seed):
    rng = np.random.default_rng(seed)
    gh, gw = int(shape[0] / scale) + 3, int(shape[1] / scale) + 3
    grid = rng.random((gh, gw)).astype(np.float32)
    y = np.arange(shape[0]) / scale
    x = np.arange(shape[1]) / scale
    y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int)
    fy = (y - y0)[:, None]; fx = (x - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    g00 = grid[y0][:, x0]; g10 = grid[y0 + 1][:, x0]; g01 = grid[y0][:, x0 + 1]; g11 = grid[y0 + 1][:, x0 + 1]
    return (g00 * (1 - fx) * (1 - fy) + g01 * fx * (1 - fy) + g10 * (1 - fx) * fy + g11 * fx * fy)


def fbm(shape, seed):
    k = 2.0 / TEX
    return (value_noise(shape, 40 * k, seed) * 0.5 + value_noise(shape, 16 * k, seed + 1) * 0.28
            + value_noise(shape, 6 * k, seed + 2) * 0.14 + value_noise(shape, 5, seed + 3) * 0.08)


def hexc(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def ground():
    xs, ys, inside, path = walk_field()
    shp = xs.shape
    n = fbm(shp, 3)
    ragged = value_noise(shp, 10 / TEX, 31) - 0.5
    inside = inside + ragged * 16
    path = path + ragged * 10
    moss = fbm(shp, 7)
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0 - 0.5
    dither = np.tile(bayer, (shp[0] // 4 + 1, shp[1] // 4 + 1))[:shp[0], :shp[1]] * 0.045
    v = n + dither
    img = np.zeros(shp + (3,), np.uint8)
    PAL = {
        "water": hexc("1a2a2e"), "wet": hexc("222c28"), "mud_d": hexc("272018"), "mud": hexc("33291d"),
        "mud_l": hexc("3f3424"), "moss_d": hexc("1f2a17"), "moss": hexc("2b3a1d"), "moss_l": hexc("3a4c24"),
        "dirt_d": hexc("2e261b"), "dirt": hexc("392f21"), "dirt_l": hexc("44382a"),
        "forest_d": hexc("0b100d"), "forest": hexc("111a14"), "forest_l": hexc("18241a"),
    }

    def put(mask, name):
        img[mask] = PAL[name]

    out = inside < 0
    # forest floor
    put(out & (v < 0.45), "forest_d"); put(out & (v >= 0.45) & (v < 0.62), "forest"); put(out & (v >= 0.62), "forest_l")
    ins = ~out
    put(ins & (v < 0.27), "water"); put(ins & (v >= 0.27) & (v < 0.33), "wet")
    put(ins & (v >= 0.33) & (v < 0.47), "mud_d"); put(ins & (v >= 0.47) & (v < 0.6), "mud"); put(ins & (v >= 0.6), "mud_l")
    mm = ins & (v >= 0.33) & (moss + dither > 0.5)
    put(mm & (moss + dither < 0.6), "moss_d"); put(mm & (moss + dither >= 0.6) & (moss + dither < 0.68), "moss"); put(mm & (moss + dither >= 0.68), "moss_l")
    rip = (inside > 0) & (v < 0.27) & ((((xs * 2).astype(int) // 3 + (ys * 2).astype(int) // 9) % 13) == 0)
    img[rip] = hexc("2c4044")
    # trodden paths
    pm = (path > 4) & (v >= 0.33) & ~(mm & (moss + dither > 0.62))
    put(pm & (v < 0.5), "dirt_d"); put(pm & (v >= 0.5) & (v < 0.62), "dirt"); put(pm & (v >= 0.62), "dirt_l")
    # soft dark edge where the forest begins
    edge = ins & (inside < 6)
    img[edge] = (img[edge] * 0.6).astype(np.uint8)
    # fine grain: pebbles and blades catching light
    fine = value_noise(shp, 2.2, 21)
    img[(fine > 0.86) & ins] = (img[(fine > 0.86) & ins] * 1.25).clip(0, 255).astype(np.uint8)
    img[(fine < 0.1)] = (img[(fine < 0.1)] * 0.8).astype(np.uint8)
    Image.fromarray(img, "RGB").save(os.path.join(OUT, "ground.png"))
    # normal map: height from the terrain noise plus fine grain; water stays flat
    hgt = n * 6.0 + value_noise(shp, 3, 41) * 0.8 + value_noise(shp, 1.3, 43) * 0.35
    hgt = np.where(ins & (v < 0.27), 0.27 * 6.0, hgt)
    gx = np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)
    gy = np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)
    nx, ny, nz = -gx * 1.6, gy * 1.6, np.ones_like(hgt)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    nimg = np.stack([(nx / L * 127.5 + 127.5), (ny / L * 127.5 + 127.5), (nz / L * 127.5 + 127.5)], -1).astype(np.uint8)
    Image.fromarray(nimg, "RGB").save(os.path.join(OUT, "ground_n.png"))
    # specular: puddles and wet mud shine in torchlight, moss and forest floor stay dull
    spec = np.full(shp, 0, np.uint8)
    spec[ins] = 22
    spec[ins & (v < 0.33)] = 110
    spec[ins & (v < 0.27)] = 230
    spec[mm] = 6
    spec[pm] = 14
    Image.fromarray(np.stack([spec] * 3, -1), "RGB").save(os.path.join(OUT, "ground_s.png"))
    return inside


def walkable_at(inside, x, y):
    tx, ty = int(x / TEX), int(y / TEX)
    if 0 <= ty < inside.shape[0] and 0 <= tx < inside.shape[1]:
        return inside[ty, tx]
    return -999


def place_props(inside):
    rnd = random.Random(11)
    props = []
    solids = []
    pts = []

    def free(x, y, d):
        for (px, py, pd) in pts:
            if (px - x) ** 2 + (py - y) ** 2 < (max(d, pd)) ** 2:
                return False
        return True

    def add(name, x, y, solid=0, spacing=8):
        pts.append((x, y, spacing))
        props.append({"name": name, "pos": [round(x), round(y)]})
        if solid:
            solids.append({"pos": [round(x), round(y)], "r": solid})

    # forest: dense pines just outside the walkable area, sparser deeper in
    for i in range(int(9000 * S * S)):
        x, y = rnd.uniform(-30, W + 30), rnd.uniform(-30, H + 60)
        d = walkable_at(inside, x, y)
        if d > -8:
            continue
        depth = -d
        if depth > 220 and rnd.random() < 0.55:
            continue
        if free(x, y, 24):
            add(rnd.choice(["pine_0", "pine_1", "pine_2", "pine_3", "pine_0", "pine_1", "dead_tree_0"]), x, y, 0, 24)
    # ground cover inside the walkable area
    for i in range(int(2600 * S * S)):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        d = walkable_at(inside, x, y)
        if d < 3:
            continue
        r = rnd.random()
        name = ("grass_%d" % rnd.randint(0, 3)) if r < 0.62 else rnd.choice(["mushrooms_0", "mushrooms_1", "fern", "reeds", "bones", "fern"])
        if free(x, y, 5):
            add(name, x, y, 0, 5)

    def ring(area, names, n, frac, solid=0, jitter=0.0, start=0.0):
        cx, cy = area["pos"]
        for k in range(n):
            a = start + k / n * math.tau + rnd.uniform(-jitter, jitter)
            x = cx + math.cos(a) * area["r"] * frac
            y = cy + math.sin(a) * area["r"] * frac * 0.85
            name = names[k % len(names)]
            if any(seg_dist((x, y), p["a"], p["b"]) < p["hw"] + 14 for p in PATHS):
                continue
            add(name, x, y, solid, 20)

    A = {a["id"]: a for a in AREAS}
    # camp
    add("moth_shrine", SHRINE[0], SHRINE[1], 14, 26)
    add("campfire", CAMPFIRE[0], CAMPFIRE[1], 10, 20)
    for (dx, dy) in [(-30, 6), (30, 14), (2, 34)]:
        add("rock_2", CAMPFIRE[0] + dx, CAMPFIRE[1] + dy, 0, 10)
    ring(A["camp"], ["rock_0", "dead_tree_1", "rock_1"], 5, 0.82, 10, 0.2, 0.4)
    # glade: gibbets and standing stones
    ring(A["glade"], ["gibbet", "standing_stone", "gibbet", "corpse_0", "rock_0", "corpse_1"], 9, 0.72, 0, 0.15, 0.3)
    add("standing_stone", 600 * S, 610 * S, 11, 20); add("standing_stone", 690 * S, 680 * S, 11, 20)
    # chapel: ruined walls in a broken ring, braziers
    ring(A["chapel"], ["ruin_wall_0", "ruin_wall_1", "ruin_wall_2"], 8, 0.86, 0, 0.05, 0.2)
    for (dx, dy) in [(-60, -40), (60, -40), (-60, 50), (60, 50)]:
        add("brazier", A["chapel"]["pos"][0] + dx * S, A["chapel"]["pos"][1] + dy * S, 6, 16)
    add("standing_stone", 1080 * S, 690 * S, 11, 20)
    # hollow: dead trees and boulders
    ring(A["hollow"], ["dead_tree_0", "rock_0", "dead_tree_1", "rock_1", "bones", "corpse_2"], 10, 0.74, 0, 0.2, 0.1)
    add("rock_0", 1150 * S, 300 * S, 12, 20); add("rock_0", 1220 * S, 360 * S, 12, 20)
    # pit: ring of ruins, braziers, gibbets
    ring(A["pit"], ["ruin_wall_1", "gibbet", "ruin_wall_2", "ruin_wall_0", "gibbet"], 10, 0.9, 0, 0.04, 0.0)
    for k in range(4):
        a = k / 4 * math.tau + 0.78
        add("brazier", A["pit"]["pos"][0] + math.cos(a) * 95 * S, A["pit"]["pos"][1] + math.sin(a) * 80 * S, 6, 16)
    # torches along the paths
    torches = []
    for p in PATHS[:4]:
        for t in (0.35, 0.7):
            x = p["a"][0] + (p["b"][0] - p["a"][0]) * t
            y = p["a"][1] + (p["b"][1] - p["a"][1]) * t
            dx, dy = p["b"][0] - p["a"][0], p["b"][1] - p["a"][1]
            L = math.hypot(dx, dy)
            x += -dy / L * (p["hw"] - 6); y += dx / L * (p["hw"] - 6)
            add("torch", x, y, 0, 10)
            torches.append([round(x), round(y)])
    return props, solids, torches


def seals():
    """Thorn barriers where paths enter each encounter area."""
    out = {}
    for a in AREAS:
        if not a["encounter"] or not a.get("seal", False):
            continue
        lst = []
        for p in PATHS:
            for end, other in ((p["a"], p["b"]), (p["b"], p["a"])):
                if end == a["pos"]:
                    dx, dy = other[0] - end[0], other[1] - end[1]
                    L = math.hypot(dx, dy)
                    lst.append({"pos": [round(end[0] + dx / L * (a["r"] - 4)), round(end[1] + dy / L * (a["r"] - 4))], "r": p["hw"] + 6})
        out[a["id"]] = lst
    return out


def main():
    inside = ground()
    props, solids, torches = place_props(inside)
    data = {
        "size": [W, H], "tex": TEX, "areas": AREAS, "paths": PATHS, "gate": GATE, "shrine": SHRINE,
        "campfire": CAMPFIRE, "route": ROUTE, "props": props, "solids": solids, "torches": torches, "seals": seals(),
    }
    with open(os.path.join(OUT, "level.json"), "w") as f:
        json.dump(data, f)
    print("props", len(props), "solids", len(solids))


if __name__ == "__main__":
    main()
