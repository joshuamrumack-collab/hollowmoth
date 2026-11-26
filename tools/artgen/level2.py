"""Builds Act II 'The Cinderveil': layout JSON for the land beyond the rift.

Reuses level.py's walkability field (areas = circles, paths = capsules) with
an ash-waste layout: three boss arenas (the Glass Mourner, the Mother of Moths,
Ashmaw the Chained) joined by encounter areas and a shortcut gate.
usage: python level2.py <assets folder>   -> writes level_2.json
"""
import json, math, os, random, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import level as Lv

W, H = 1700, 1200
AREAS = [
    {"id": "camp", "name": "The Rift's Edge", "pos": [260, 1000], "r": 115, "encounter": []},
    {"id": "ashfield", "name": "The Ash Fields", "pos": [660, 920], "r": 140,
     "encounter": ["ghoul", "ghoul", "ghoul", "cultist", "ghoul", "cultist", "ghoul", "brute"]},
    {"id": "mirror", "name": "The Hall of Mirrors", "pos": [1110, 980], "r": 150, "boss": True, "seal": True,
     "encounter": ["mirror_wraith"],
     "bossinfo": {"title": "THE GLASS MOURNER", "sub": "She weeps for faces that are not hers", "intro": "wraith_intro", "dead": "wraith_dead",
                  "victory": "The mirrors go dark. Something in them was grateful.", "music": "boss"}},
    {"id": "ossuary", "name": "The Ossuary Road", "pos": [1300, 580], "r": 140,
     "encounter": ["brute", "ghoul", "brute", "cultist", "ghoul", "cultist", "ghoul", "cultist"]},
    {"id": "grove", "name": "The Moth Grove", "pos": [880, 520], "r": 155, "boss": True, "seal": True,
     "encounter": ["shadow_moth"],
     "bossinfo": {"title": "THE MOTHER OF MOTHS", "sub": "The Black Butterfly's lost shadow", "intro": "moth_intro", "dead": "moth_dead",
                  "victory": "The dark wings unravel into a thousand small and harmless moths.", "music": "boss"}},
    {"id": "throne", "name": "Ashmaw's Throne", "pos": [420, 300], "r": 195, "boss": True, "final": True, "seal": True,
     "encounter": ["dragon"],
     "bossinfo": {"title": "ASHMAW THE CHAINED", "sub": "The wyrm the Iron Brother kept on a leash", "intro": "dragon_intro", "dead": "dragon_dead",
                  "victory": "Ashmaw is dead. The chains finally go quiet.", "music": "boss"}},
]
PATHS = [
    {"a": [260, 1000], "b": [660, 920], "hw": 34},
    {"a": [660, 920], "b": [1110, 980], "hw": 34},
    {"a": [1110, 980], "b": [1300, 580], "hw": 34},
    {"a": [1300, 580], "b": [880, 520], "hw": 34},
    {"a": [880, 520], "b": [420, 300], "hw": 38},
    # shortcut: the Moth Grove back down to the Ash Fields, through an iron gate
    {"a": [880, 520], "b": [660, 920], "hw": 28},
]
GATE = {"pos": [752, 753], "r": 30, "open_from": [0.48, -0.87]}
SHRINE = [242, 950]
CAMPFIRE = [292, 1022]
RIFT = [170, 1040]
ROUTE = [[260, 1000], [460, 960], [660, 920], [880, 950], [1110, 980], [1200, 780], [1300, 580],
         [1090, 550], [880, 520], [650, 410], [420, 300]]
S = 1.4
Lv.scale_layout(globals(), S, 1.25)


def install():
    Lv.W, Lv.H = W, H
    Lv.AREAS, Lv.PATHS = AREAS, PATHS


def field():
    install()
    xs, ys, inside, path = Lv.walk_field()
    shp = xs.shape
    ragged = Lv.value_noise(shp, 10 / Lv.TEX, 31) - 0.5
    return xs, ys, inside + ragged * 16, path + ragged * 10, ragged


def place_props(inside):
    rnd = random.Random(23)
    props, solids, pts = [], [], []

    def free(x, y, d):
        return all((px - x) ** 2 + (py - y) ** 2 >= max(d, pd) ** 2 for (px, py, pd) in pts)

    def add(name, x, y, solid=0, spacing=8):
        pts.append((x, y, spacing))
        props.append({"name": name, "pos": [round(x), round(y)]})
        if solid:
            solids.append({"pos": [round(x), round(y)], "r": solid})

    # the waste: dead trees, boulders and the odd standing stone outside the walkable area
    for i in range(int(9000 * S * S)):
        x, y = rnd.uniform(-30, W + 30), rnd.uniform(-30, H + 60)
        d = Lv.walkable_at(inside, x, y)
        if d > -8:
            continue
        if -d > 200 and rnd.random() < 0.6:
            continue
        if free(x, y, 26):
            add(rnd.choice(["dead_tree_0", "dead_tree_1", "dead_tree_0", "rock_0", "rock_1", "dead_tree_1", "standing_stone", "ruin_wall_1"]), x, y, 0, 26)
    # sparse cover inside: bones and dead grass, little else lives here
    for i in range(int(1800 * S * S)):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        if Lv.walkable_at(inside, x, y) < 3:
            continue
        r = rnd.random()
        name = ("grass_%d" % rnd.randint(2, 3)) if r < 0.4 else rnd.choice(["bones", "bones", "rock_2", "mushrooms_1", "corpse_0", "grass_1"])
        if free(x, y, 7):
            add(name, x, y, 0, 7)

    def ring(area, names, n, frac, solid=0, jitter=0.0, start=0.0):
        cx, cy = area["pos"]
        for k in range(n):
            a = start + k / n * math.tau + rnd.uniform(-jitter, jitter)
            x = cx + math.cos(a) * area["r"] * frac
            y = cy + math.sin(a) * area["r"] * frac * 0.85
            if any(Lv.seg_dist((x, y), p["a"], p["b"]) < p["hw"] + 14 for p in PATHS):
                continue
            add(names[k % len(names)], x, y, solid, 20)

    A = {a["id"]: a for a in AREAS}
    add("moth_shrine", SHRINE[0], SHRINE[1], 14, 26)
    add("campfire", CAMPFIRE[0], CAMPFIRE[1], 10, 20)
    ring(A["camp"], ["rock_0", "dead_tree_1", "rock_1"], 5, 0.84, 10, 0.2, 0.9)
    ring(A["ashfield"], ["gibbet", "corpse_1", "dead_tree_0", "corpse_2", "rock_0"], 9, 0.74, 0, 0.2, 0.2)
    # the hall: broken walls and tall stones that once held mirrors
    ring(A["mirror"], ["ruin_wall_0", "standing_stone", "ruin_wall_2", "standing_stone", "ruin_wall_1"], 10, 0.88, 0, 0.03, 0.15)
    for k in range(4):
        a = k / 4 * math.tau + 0.78
        add("brazier", A["mirror"]["pos"][0] + math.cos(a) * 80 * S, A["mirror"]["pos"][1] + math.sin(a) * 66 * S, 6, 16)
    ring(A["ossuary"], ["bones", "gibbet", "corpse_0", "ruin_wall_2", "bones", "corpse_1"], 10, 0.76, 0, 0.2, 0.0)
    add("rock_0", 1270 * S, 560 * S, 12, 20); add("rock_0", 1340 * S, 610 * S, 12, 20)
    # the grove: dead trees wrapped in moths
    ring(A["grove"], ["dead_tree_0", "moth_0", "dead_tree_1", "moth_1"], 12, 0.8, 0, 0.12, 0.1)
    # the throne: a ring of ruins, braziers and the wyrm's chains (gibbets)
    ring(A["throne"], ["ruin_wall_1", "gibbet", "ruin_wall_0", "ruin_wall_2", "gibbet", "standing_stone"], 12, 0.92, 0, 0.03, 0.0)
    for k in range(6):
        a = k / 6 * math.tau + 0.5
        add("brazier", A["throne"]["pos"][0] + math.cos(a) * 125 * S, A["throne"]["pos"][1] + math.sin(a) * 100 * S, 6, 16)
    torches = []
    for p in PATHS[:5]:
        for t in (0.35, 0.7):
            x = p["a"][0] + (p["b"][0] - p["a"][0]) * t
            y = p["a"][1] + (p["b"][1] - p["a"][1]) * t
            dx, dy = p["b"][0] - p["a"][0], p["b"][1] - p["a"][1]
            L = math.hypot(dx, dy)
            x += -dy / L * (p["hw"] - 6); y += dx / L * (p["hw"] - 6)
            add("torch", x, y, 0, 10)
            torches.append([round(x), round(y)])
    return props, solids, torches


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else Lv.OUT
    xs, ys, inside, path, ragged = field()
    props, solids, torches = place_props(inside)
    data = {
        "act": 2, "title": "ACT II: THE CINDERVEIL", "ground": "ground2",
        "size": [W, H], "tex": Lv.TEX, "areas": AREAS, "paths": PATHS, "gate": GATE, "shrine": SHRINE,
        "campfire": CAMPFIRE, "rift": RIFT, "route": ROUTE, "props": props, "solids": solids, "torches": torches,
        "seals": Lv.seals(), "night": [0.42, 0.34, 0.36], "ash": True,
    }
    with open(os.path.join(out, "level_2.json"), "w") as f:
        json.dump(data, f)
    print("act2 props", len(props), "solids", len(solids))


if __name__ == "__main__":
    main()
