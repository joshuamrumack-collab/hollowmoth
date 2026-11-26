"""Overview renders for comparing layouts (not used by the game).

  A: the real Act I (assets/ground.png + level.json props)
  B: a mockup of a hand-authored layout (the kind of shapes Tiled allows),
     painted with the same textures and props.
usage: python map_compare.py <art folder> <assets folder> <out.png>
"""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import level as Lv

ART, ASSETS, OUT = (sys.argv[1:4] + ["", "", ""])[:3] if __name__ == "__main__" else ("", "", "")
W, H = 2400, 1650          # world units (same as the current Act I)
PX = 0.5                   # overview pixels per world unit
OW, OH = int(W * PX), int(H * PX)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
man = json.load(open(os.path.join(ASSETS or os.path.join(os.path.dirname(__file__), "../../assets"), "manifest.json")))["props"]
_cache = {}


def prop_img(name):
    if name not in _cache:
        p = os.path.join(ASSETS, "prop_%s.png" % name)
        if not os.path.exists(p) or name not in man:
            _cache[name] = None
        else:
            im = Image.open(p).convert("RGBA")
            s = man[name]["scale"] * PX
            _cache[name] = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    return _cache[name]


def draw_props(base, props):
    for p in sorted(props, key=lambda q: q["pos"][1]):
        im = prop_img(p["name"])
        if im is None:
            continue
        x, y = p["pos"][0] * PX, p["pos"][1] * PX
        base.alpha_composite(im, (int(x - im.width / 2), int(y - im.height)))


def label(base, items):
    d = ImageDraw.Draw(base)
    f = ImageFont.truetype(FONT, 15)
    for text, (x, y), col in items:
        x, y = x * PX, y * PX
        tw = d.textlength(text, font=f)
        d.text((x - tw / 2 + 1, y + 1), text, font=f, fill=(0, 0, 0, 230))
        d.text((x - tw / 2, y), text, font=f, fill=col)


def night(base, amount=0.82):
    a = np.asarray(base).astype(np.float32)
    a[..., :3] *= amount
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ A: current
def current():
    g = Image.open(os.path.join(ASSETS, "ground.png")).convert("RGBA").resize((OW, OH), Image.LANCZOS)
    L = json.load(open(os.path.join(ASSETS, "level.json")))
    draw_props(g, L["props"])
    g = night(g)
    label(g, [(a["name"], (a["pos"][0], a["pos"][1] - a["r"] * 0.15), (235, 215, 170)) for a in L["areas"]])
    return g


# ------------------------------------------------------------------ B: hand-authored mockup
# Walkable shapes as polygons, roads as polylines with a width, plus water.
CLEARINGS = {
    "camp": [(250, 1180), (420, 1130), (540, 1210), (520, 1380), (380, 1450), (230, 1390)],
    "crossroads": [(780, 1020), (980, 960), (1120, 1040), (1130, 1210), (990, 1330), (800, 1300), (720, 1180)],
    "hermit": [(560, 760), (680, 720), (740, 800), (690, 880), (590, 880)],
    "quarry": [(640, 280), (900, 220), (1080, 300), (1120, 470), (960, 600), (720, 590), (600, 450)],
    "village": [(1480, 960), (1820, 900), (2080, 1000), (2120, 1230), (1940, 1400), (1600, 1390), (1440, 1220)],
    "pit": [(1650, 250), (1880, 170), (2120, 260), (2180, 470), (2040, 640), (1760, 650), (1620, 480)],
}
ROADS = [
    ([(470, 1300), (620, 1240), (760, 1180)], 46),            # camp -> crossroads
    ([(870, 1020), (800, 900), (690, 800)], 34),              # crossroads -> hermit's hollow (dead end)
    ([(930, 980), (930, 820), (880, 700), (860, 590)], 34),   # crossroads -> quarry (narrow canyon)
    ([(1120, 1130), (1290, 1110), (1460, 1120)], 44),         # crossroads -> bridge -> village
    ([(1080, 380), (1300, 380), (1640, 390)], 42),            # quarry -> ford -> pit
    ([(1800, 920), (1840, 780), (1860, 650)], 40),            # village -> pit (the loop back)
]
RIVERS = [([(1320, -40), (1260, 200), (1330, 420), (1270, 700), (1230, 950), (1290, 1110), (1240, 1350), (1300, 1700)], 35)]
FLOORS = {"village": "flag", "pit": "bones"}   # clearing id -> floor painting (flag, bones, mud)
DRESSING = {}                                  # clearing id -> prop names scattered inside (optional)
HOUSES = [(1600, 1060), (1760, 1020), (1960, 1100), (1650, 1300), (1900, 1300)]
CROSSINGS = [((1290, 1110), "bridge"), ((1300, 385), "ford")]


def raster_mask(scale):
    """Walkable mask at `scale` px per world unit."""
    w, h = int(W * scale), int(H * scale)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    for poly in CLEARINGS.values():
        d.polygon([(x * scale, y * scale) for x, y in poly], fill=255)
    for pts, hw in ROADS:
        d.line([(x * scale, y * scale) for x, y in pts], fill=255, width=int(hw * 2 * scale), joint="curve")
        for x, y in pts:
            r = hw * scale
            d.ellipse((x * scale - r, y * scale - r, x * scale + r, y * scale + r), fill=255)
    road = Image.new("L", (w, h), 0)
    rd = ImageDraw.Draw(road)
    for pts, hw in ROADS:
        rd.line([(x * scale, y * scale) for x, y in pts], fill=255, width=int(hw * 1.2 * scale), joint="curve")
    water = Image.new("L", (w, h), 0)
    wd = ImageDraw.Draw(water)
    for pts, hw in RIVERS:
        wd.line([(x * scale, y * scale) for x, y in pts], fill=255, width=int(hw * 2 * scale), joint="curve")
    return np.asarray(m) > 0, np.asarray(road) > 0, np.asarray(water) > 0


def tile(name, size, shape):
    im = Image.open(os.path.join(ART, name)).convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    reps = (shape[0] // size + 2, shape[1] // size + 2, 1)
    return np.tile(a, reps)[: shape[0], : shape[1]]


PALETTE = "forest"          # forest (Act I), ash (Act II), frost (Act III)
WATER = "river"             # river, lava, ice
GLOWS = []                  # filled by paint(): [(x, y, colour)] spots that want a light in game


def _grade(a, tgt, tint, sat):
    """Re-grade a painted texture: saturation, brightness target, colour tint."""
    g = a.mean(-1, keepdims=True)
    a = g + (a - g) * sat
    a = a * (tgt / max(1.0, a.mean()))
    return a * np.array(tint, np.float32)


_TEX = {}


def _tex(name, size):
    key = (name, size)
    if key not in _TEX:
        im = Image.open(os.path.join(ART, name)).convert("RGB").resize((size, size), Image.LANCZOS)
        _TEX[key] = np.asarray(im).astype(np.float32)
    return _TEX[key]


def _band(name, size, y0, y1, w):
    t = _tex(name, size)
    return t[(np.arange(y0, y1) % size)][:, (np.arange(w) % size)]


def paint(px, art):
    """The layout's ground at px pixels per world unit: (image, signed distance, water mask, walk mask).
    Painted in horizontal bands so big maps fit in memory."""
    global ART, GLOWS
    ART = art
    GLOWS = []
    k = px / 0.5
    walk, road, water = raster_mask(px)
    shape = walk.shape
    hh, ww = shape
    f32 = np.float32
    sd = ((ndimage.distance_transform_edt(walk) - ndimage.distance_transform_edt(~walk)) / px).astype(f32)
    sd += ((Lv.value_noise(shape, 6 * k, 31) - 0.5) * 16).astype(f32)
    road_b = ndimage.gaussian_filter(road.astype(f32), 3 * k)
    wsm = ndimage.gaussian_filter(water.astype(f32), 2 * k)
    wedge = np.clip(ndimage.gaussian_filter(water.astype(f32), 5 * k) - wsm, 0, 1)
    blend = Lv.value_noise(shape, 22 * k, 5).astype(f32)
    n1 = Lv.value_noise(shape, 4 * k, 9).astype(f32)
    n2 = Lv.value_noise(shape, 14 * k, 19).astype(f32) if WATER == "lava" else None
    floors = []
    emb = None
    for cid, fl in FLOORS.items():
        if cid not in CLEARINGS or fl not in ("flag", "bones", "mud", "embers", "snow"):
            continue
        m = Image.new("L", (ww, hh), 0)
        ImageDraw.Draw(m).polygon([(x * px, y * px) for x, y in CLEARINGS[cid]], fill=255)
        mm = ndimage.gaussian_filter(np.asarray(m).astype(f32) / 255, 8 * k)
        floors.append((fl, np.clip((mm - 0.35) * 2.2, 0, 1)))
        if fl == "embers" and emb is None:
            emb = (Lv.value_noise(shape, 16.0 * k, 77) * 0.65 + Lv.value_noise(shape, 3.5 * k, 78) * 0.35).astype(f32)
    sm = lambda x: np.clip(x, 0, 1) ** 2 * (3 - 2 * np.clip(x, 0, 1))
    grade = {
        "ash": {"mud": (62, [1.08, 1.0, 0.95], 0.25), "moss": (50, [0.98, 0.92, 1.05], 0.3), "forest": (20, [1.05, 0.9, 0.88], 0.3),
                "flag": (68, [1.0, 0.97, 0.95], 0.4), "bones": (62, [1.15, 0.95, 0.85], 0.7)},
        "frost": {"mud": (86, [0.92, 0.98, 1.1], 0.25), "moss": (108, [0.9, 0.98, 1.12], 0.15), "forest": (30, [0.78, 0.9, 1.1], 0.35),
                  "flag": (92, [0.9, 0.96, 1.1], 0.3), "bones": (90, [0.92, 0.97, 1.08], 0.4)},
    }.get(PALETTE)
    # brightness targets need whole-texture means: grade the source tiles once
    def tex_band(kind, file, size, y0, y1):
        t = _band(file, size, y0, y1, ww)
        if grade:
            tgt, tint, sat = grade[kind]
            src = _tex(file, size)
            g = t.mean(-1, keepdims=True)
            t = g + (t - g) * sat
            t = t * (tgt / max(1.0, src.mean())) / max(0.2, (sat + (1 - sat) * 1.0))
            t = t * np.array(tint, f32)
        else:
            t = t * {"mud": 0.9, "moss": 0.8, "flag": 0.8, "bones": 0.75, "forest": 1.0}[kind]
            if kind == "forest":
                t = t * np.array([0.22, 0.28, 0.24], f32)
        return t
    out = np.zeros((hh, ww, 3), np.uint8)
    B = 384
    for y0 in range(0, hh, B):
        y1 = min(hh, y0 + B)
        sl = slice(y0, y1)
        mud = tex_band("mud", "mud.jpg", int(140 * k), y0, y1)
        moss = tex_band("moss", "moss.jpg", int(120 * k), y0, y1)
        forest = tex_band("forest", "moss.jpg", int(105 * k), y0, y1)
        bl = blend[sl][..., None]
        clear = moss * (1 - bl) + mud * bl
        rd = road_b[sl][..., None]
        clear = clear * (1 - rd) + mud * 1.05 * rd
        emb_mask = np.zeros((y1 - y0, ww), f32)
        for fl, mm in floors:
            m_ = mm[sl]
            if m_.max() <= 0:
                continue
            if fl == "flag":
                tex = tex_band("flag", "flag.jpg", int(180 * k), y0, y1)
            elif fl in ("bones", "embers"):
                tex = tex_band("bones", "bones.jpg", int(140 * k), y0, y1)
            elif fl == "snow":
                tex = moss * 1.15
            else:
                tex = mud
            clear = clear * (1 - m_[..., None]) + tex * m_[..., None]
            if fl == "embers":
                emb_mask = np.maximum(emb_mask, m_)
        sdb = sd[sl]
        # a crisp edge: the walkable ground stays lit right up to its border (with a pale worn lip),
        # the ground beyond drops into shadow and is greyed out, so you can read where you can go
        w_in = sm((sdb + 2) / 6)[..., None]
        img = forest * (1 - w_in) + clear * w_in
        outm = (1 - sm((sdb + 3) / 14))[..., None]
        grey = img.mean(-1, keepdims=True)
        img = (img * (1 - 0.5 * outm) + grey * 0.5 * outm) * (1 - 0.62 * outm)
        img *= (1 + 0.14 * sm((sdb - 2) / 6))[..., None]            # the path itself a touch brighter
        shade = (sm((sdb + 14) / 9) * (1 - sm((sdb + 1) / 2.5)))[..., None]
        img *= (1 - 0.6 * shade)
        lip = (sm(sdb / 1.5) * (1 - sm((sdb - 5) / 3)))[..., None]
        img += lip * np.array([48.0, 41.0, 28.0], f32)
        if emb is not None and emb_mask.max() > 0:
            glow = (0.85 * sm((emb[sl] - 0.74) / 0.06) * emb_mask)[..., None]
            img = img * (1 - glow) + np.array([210.0, 80.0, 30.0], f32) * glow
        ws = wsm[sl][..., None]
        we = wedge[sl][..., None]
        nn = n1[sl][..., None]
        if WATER == "lava":
            hot = np.clip(n2[sl][..., None] * 1.4 - 0.2, 0, 1)
            wat = np.array([120, 30, 8], f32) * (1 - hot) + np.array([255, 150, 40], f32) * hot + nn * 30
            img = img * (1 - ws) + wat * ws + we * np.array([60, 20, 0], f32)
        elif WATER == "ice":
            wat = np.array([14, 24, 32], f32) + nn * 12
            img = img * (1 - ws) + wat * ws + we * np.array([70, 80, 95], f32)
        else:
            # moonlit water: lighter than the forest floor, with a pale ripple, so it reads at night
            rip = np.clip(np.sin((np.arange(y0, y1, dtype=f32)[:, None] * 0.09 + nn[..., 0] * 9.0)) * 0.5 + 0.5, 0, 1)[..., None]
            wat = np.array([40, 60, 78], f32) + nn * 24 + rip * np.array([14, 20, 26], f32)
            img = img * (1 - ws) + wat * ws + we * 30
        out[sl] = np.clip(img, 0, 255).astype(np.uint8)
    # lights along lava (and over ember floors) so they glow at night in game
    if True:
        step = 140 if WATER == "lava" else 230
        for pts, hw in RIVERS:
            for i in range(len(pts) - 1):
                (ax, ay), (bx, by) = pts[i], pts[i + 1]
                n = max(1, int(math.hypot(bx - ax, by - ay) / step))
                for t in range(n):
                    f = (t + 0.5) / n
                    GLOWS.append((ax + (bx - ax) * f, ay + (by - ay) * f, "lava" if WATER == "lava" else "water"))
    for cid, fl in FLOORS.items():
        if fl == "embers" and cid in CLEARINGS:
            xs_ = [p[0] for p in CLEARINGS[cid]]; ys_ = [p[1] for p in CLEARINGS[cid]]
            GLOWS.append((sum(xs_) / len(xs_), sum(ys_) / len(ys_), "embers"))
    g = Image.fromarray(out, "RGB").convert("RGBA")
    _crossings(g, px)
    return g, sd, water, walk


def crossing_frame(x, y):
    """Across-the-water unit vector, half-length and half-width for a crossing at (x, y)."""
    best = None
    for pts, hw in RIVERS:
        for i in range(len(pts) - 1):
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            dx, dy = bx - ax, by - ay
            L2 = dx * dx + dy * dy or 1.0
            t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L2))
            d = math.hypot(x - (ax + t * dx), y - (ay + t * dy))
            if best is None or d < best[0]:
                L = math.sqrt(L2)
                best = (d, (-dy / L, dx / L), hw)
    if best is None:
        return (1.0, 0.0), 44.0, 30.0
    return best[1], best[2] + 34.0, 30.0


def _crossings(g, px):
    d = ImageDraw.Draw(g)
    plank = {"ash": (70, 58, 50), "frost": (120, 116, 112)}.get(PALETTE, (92, 70, 48))
    rail = tuple(int(c * 0.65) for c in plank)
    for (x, y), kind in CROSSINGS:
        (ux, uy), half, wide = crossing_frame(x, y)
        vx, vy = -uy, ux   # along the water
        P = lambda a, b: ((x + ux * a + vx * b) * px, (y + uy * a + vy * b) * px)
        if kind == "bridge":
            for k in range(-4, 5):
                b0, b1 = k * 6.4 - 2.8, k * 6.4 + 2.8
                d.polygon([P(-half, b0), P(half, b0), P(half, b1), P(-half, b1)], fill=plank)
            for side in (-wide, wide):
                d.line([P(-half, side), P(half, side)], fill=rail, width=max(2, int(4 * px)))
        else:
            rnd = random.Random(3)
            n = int(half * 2 / 11)
            for k in range(n):
                cx_, cy_ = P(-half + 6 + k * 11, rnd.uniform(-12, 12))
                d.ellipse((cx_ - 6 * px, cy_ - 4 * px, cx_ + 6 * px, cy_ + 4 * px), fill=(96, 94, 88) if PALETTE != "ash" else (70, 64, 60))


FOREST = {
    "forest": ["pine_0", "pine_1", "pine_2", "pine_1", "pine_0", "dead_tree_0", "rock_0"],
    "ash": ["dead_tree_0", "dead_tree_1", "dead_tree_0", "rock_0", "rock_1", "dead_tree_1", "standing_stone", "ruin_wall_1"],
    "frost": ["pine_0", "pine_1", "pine_2", "pine_1", "rock_0", "rock_1", "dead_tree_0"],
}
DRESS = {
    "forest": ["grass_1", "grass_2", "fern", "rock_2", "mushrooms_1", "ud_bush_1", "ud_stump_0"],
    "ash": ["bones", "bones", "rock_2", "corpse_0", "grass_3", "ud_bones_0", "ud_bones_1", "ud_bones_2"],
    "frost": ["rock_2", "grass_1", "bones", "rock_1", "ud_grave_0", "ud_grave_3", "ud_crystal_1", "cem_stone_0", "cem_stone_3"],
}
# a hedge of obstacles just outside every walkable edge (the Undead tileset), so borders read as walls
EDGE = {
    "forest": ["ud_thorn_0", "ud_thorn_1", "ud_thorn_2", "ud_thorn_2", "ud_deadtree_0", "ud_tree_0", "ud_tree_1",
               "ud_rock_0", "ud_rock_1", "ud_bush_0", "ud_log_0", "ud_stump_0"],
    "ash": ["ud_rock_0", "ud_rock_1", "ud_rock_2", "ud_deadtree_0", "ud_deadtree_1", "ud_ruin_2", "ud_arm_0",
            "ud_arm_1", "ud_arm_2", "ud_arm_3", "ud_skulls", "ud_thorn_1", "ud_rock_2"],
    "frost": ["ud_rock_0", "ud_rock_1", "ud_rock_2", "ud_crystal_0", "ud_crystal_1", "ud_crystal_0", "ud_ruin_2",
              "cem_cross_0", "cem_cross_2", "cem_cross_4", "cem_stone_1", "cem_stone_2", "ud_deadtree_1", "ud_thorn_2"],
}


def mock_props(sd, water, px):
    """Forest outside, set dressing inside (world coordinates)."""
    shape = sd.shape
    rnd = random.Random(11)
    props = []
    cell = 40.0
    grid = {}

    def free(x, y, r):
        gx, gy = int(x // cell), int(y // cell)
        for i in range(gx - 1, gx + 2):
            for j in range(gy - 1, gy + 2):
                for qx, qy, qr in grid.get((i, j), ()):
                    if (qx - x) ** 2 + (qy - y) ** 2 < max(r, qr) ** 2:
                        return False
        return True

    def put(x, y, r, name):
        grid.setdefault((int(x // cell), int(y // cell)), []).append((x, y, r))
        props.append({"name": name, "pos": [x, y]})

    def at(x, y):
        ix, iy = int(np.clip(x * px, 0, shape[1] - 1)), int(np.clip(y * px, 0, shape[0] - 1))
        return sd[iy, ix], water[iy, ix]

    # the hedge first: close outside the edge, never on water
    edge = EDGE.get(PALETTE, EDGE["forest"])
    tries = int(60000 * (W * H) / (2400 * 1650))
    for i in range(tries):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        s, wet = at(x, y)
        if s > -9 or s < -30 or wet:
            continue
        # tall pieces lean north: keep their tops from covering the path to the south
        if free(x, y, 17):
            put(x, y, 17, rnd.choice(edge))
    trees = FOREST.get(PALETTE, FOREST["forest"])
    tries = int(26000 * (W * H) / (2400 * 1650))
    for i in range(tries):
        x, y = rnd.uniform(-20, W + 20), rnd.uniform(-20, H + 80)
        s, wet = at(x, y)
        # a tree's crown reaches ~60 units up from its foot: keep it off roads and clearings
        if s > -10 or wet or at(x, y - 25)[0] > -4 or at(x, y - 50)[0] > 0 or at(x, y - 50)[1]:
            continue
        if free(x, y, 30):
            put(x, y, 30, rnd.choice(trees))
    for cid, poly in CLEARINGS.items():
        choice = DRESSING.get(cid) or DRESS.get(PALETTE, DRESS["forest"])
        xs_ = [p[0] for p in poly]; ys_ = [p[1] for p in poly]
        n = int(60 * max(1.0, (max(xs_) - min(xs_)) * (max(ys_) - min(ys_)) / 160000))
        for i in range(n):
            x, y = rnd.uniform(min(xs_), max(xs_)), rnd.uniform(min(ys_), max(ys_))
            s, wet = at(x, y)
            if s < 12 or wet or not free(x, y, 34):
                continue
            put(x, y, 34, rnd.choice(choice))
    for hx, hy in HOUSES:
        for k in range(2):
            props.append({"name": "ruin_wall_%d" % (k % 3), "pos": [hx + k * 34 - 17, hy]})
    return props


def mockup():
    g, sd, water, walk = paint(PX, ART)
    props = mock_props(sd, water, PX) + [{"name": "moth_shrine", "pos": [350, 1250]}, {"name": "campfire_0", "pos": [420, 1330]}, {"name": "gate", "pos": [1840, 700]}]
    draw_props(g, props)
    g = night(g)
    label(g, [
        ("Camp & Shrine", (380, 1420), (235, 215, 170)),
        ("Gallows Crossroads", (950, 1300), (235, 215, 170)),
        ("Hermit's Hollow", (650, 900), (190, 200, 160)),
        ("(optional, loot)", (650, 935), (150, 160, 130)),
        ("Brute Quarry", (860, 560), (235, 215, 170)),
        ("narrow canyon", (990, 760), (150, 160, 130)),
        ("Drowned Village", (1780, 1380), (235, 215, 170)),
        ("alleys between houses", (1780, 1415), (150, 160, 130)),
        ("bridge", (1290, 1160), (150, 170, 190)),
        ("ford", (1300, 430), (150, 170, 190)),
        ("Iron Brother's Pit", (1900, 600), (235, 215, 170)),
        ("gate: loop back", (1990, 760), (150, 160, 130)),
    ])
    return g


def main():
    a, b = current(), mockup()
    f = ImageFont.truetype(FONT, 22)
    pad, head = 16, 44
    out = Image.new("RGBA", (OW, (OH + head + pad) * 2 + pad), (14, 12, 12, 255))
    d = ImageDraw.Draw(out)
    d.text((pad, pad), "NOW: generated (circles joined by straight roads)", font=f, fill=(235, 215, 170))
    out.alpha_composite(a, (0, head + pad))
    y2 = OH + head + pad * 2
    d.text((pad, y2), "MOCKUP: hand-drawn in Tiled (free shapes, river, side areas, loops)", font=f, fill=(235, 215, 170))
    out.alpha_composite(b, (0, y2 + head))
    out.convert("RGB").save(OUT, quality=90)
    a.convert("RGB").save(OUT.replace(".png", "_now.png"))
    b.convert("RGB").save(OUT.replace(".png", "_tiled.png"))
    print(out.size)


if __name__ == "__main__":
    main()
