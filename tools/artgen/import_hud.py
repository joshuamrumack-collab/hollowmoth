"""Split DorkTeach's HUD sheet into layered pieces for the game HUD.

Orbs become glass / liquid / shine / frame layers so the liquid can drain;
bars become frame + fill so code can draw any fill amount.
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as nd

SRC, OUT = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(__file__), "import_concepts.py")).read()
ns = {"__file__": os.path.join(os.path.dirname(__file__), "import_concepts.py")}
exec(src.split("cuts = {i")[0].replace("SRC = sys.argv[1]", "SRC=''").replace("OUT = sys.argv[2]", "OUT=''"), ns)
fg, alpha, comp, boxes = ns["cutout"](SRC)
RGBA = np.dstack([fg, alpha * 255]).astype(np.float32)
meta = {}


def crop(x0, y0, x1, y1):
    return RGBA[y0:y1, x0:x1].copy()


def save(name, arr, scale=0.5):
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    if scale != 1.0:
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    im.save(f"{OUT}/{name}.png")
    return im.size


# ------------------------------------------------------------- orbs
for name, box, line in [("hp", (708, 40, 1205, 497), 200), ("st", (1371, 40, 1868, 497), 195)]:
    a = crop(*box)
    H, W = a.shape[:2]
    cx, cy, R = 248, 232, 153
    yy, xx = np.mgrid[0:H, 0:W]
    inside = (xx - cx) ** 2 + (yy - cy) ** 2 <= (R - 1) ** 2
    lum = a[..., :3].mean(2)
    # liquid filling the whole sphere: mirror the painted liquid upwards
    # liquid filling the whole sphere: stretch the painted liquid (below its surface) over the full height
    edge = line + 32
    top, bot = cy - R, cy + R
    liquid = a.copy()
    for y in range(max(0, top), min(H, bot + 1)):
        ys = int(round(edge + (y - top) / (bot - top) * (bot - 6 - edge)))
        liquid[y] = a[ys]
    liquid[..., 3] = np.where(inside, 255, 0)
    # empty glass: stretch the painted glass (above the surface) down over the full height
    gl = line - 16
    glass = a.copy()
    for y in range(max(0, top), min(H, bot + 1)):
        ys = int(round(top + 6 + (y - top) / (bot - top) * (gl - top - 6)))
        glass[y] = a[ys]
    glass[..., :3] *= 0.55
    glass[..., 3] = np.where(inside, 255, 0)
    # shine: bright spots in the upper-left of the glass
    glass_mean = np.median(lum[inside & (yy < line - 10)])
    shine = a.copy()
    sm = inside & (yy < line - 16) & (lum > glass_mean + 14)
    sm = nd.binary_opening(sm, iterations=1)
    shine[..., 3] = np.where(sm, 200, 0)
    frame = a.copy()
    frame[..., 3] = np.where(inside, 0, frame[..., 3])
    for layer, arr in [("glass", glass), ("liquid", liquid), ("shine", shine), ("frame", frame)]:
        size = save(f"orb_{name}_{layer}", arr)
    s = 0.5
    meta[f"orb_{name}"] = {"size": size, "cx": cx * s, "cy": cy * s, "r": R * s}


# ------------------------------------------------------------- bars (frame + fill)
def bar(name, box, interior, fill_from):
    a = crop(*box)
    x0, y0, x1, y1 = interior
    fill = a[y0:y1, fill_from[0]:fill_from[1]].copy()
    fill[..., 3] = 255
    frame = a.copy()
    frame[y0:y1, x0:x1, 3] = 0
    size = save(f"bar_{name}_frame", frame)
    save(f"bar_{name}_fill", fill)
    meta[f"bar_{name}"] = {"size": size, "interior": [x0 * 0.5, y0 * 0.5, (x1 - x0) * 0.5, (y1 - y0) * 0.5]}
    return a


def find_interior(a, pred):
    m = pred(a)
    lab, n = nd.label(m)
    sizes = nd.sum(m, lab, range(n + 1))
    k = int(np.argmax(sizes[1:])) + 1
    s = nd.find_objects((lab == k).astype(int))[0]
    return s[1].start, s[0].start, s[1].stop, s[0].stop


boss = crop(64, 850, 2512, 1113)
red = lambda a: (a[..., 0] > a[..., 1] * 1.7) & (a[..., 0] > 70) & (a[..., 3] > 200)
rx0, ry0, rx1, ry1 = find_interior(boss, red)
dark = lambda a: (a[..., :3].max(2) < 34) & (a[..., 3] > 200)
mid = (ry0 + ry1) // 2
row = (boss[..., :3].max(2) < 60)[mid]
ex = rx1
while ex < boss.shape[1] - 1 and row[ex]:
    ex += 1
bar("boss", (64, 850, 2512, 1113), (rx0, ry0, ex, ry1), (rx0 + 40, rx1 - 40))

comp_box = (151, 1131, 1058, 1398)
cb = crop(*comp_box)
cx0, cy0, cx1, cy1 = find_interior(cb, red)
row = (cb[..., :3].max(2) < 60)[(cy0 + cy1) // 2]
ex = cx1 + 4
while ex < cb.shape[1] - 1 and row[ex]:
    ex += 1
# icons sit above the bar on this sheet: cut them out of the frame and keep them separately
icons = {"buff": (578, 1138, 669, 1226), "guard": (695, 1138, 780, 1226), "haste": (812, 1134, 905, 1226), "wound": (930, 1138, 1024, 1226)}
for k, (x0, y0, x1, y1) in icons.items():
    save(f"status_{k}", crop(x0, y0, x1, y1), 0.5)
RGBA[1131:1238, 560:1058, 3] = 0
bar("comp", comp_box, (cx0, cy0, ex, cy1), (cx0 + 10, cx1 - 10))
# the round portrait socket on the companion bar
cbm = crop(*comp_box)
meta["bar_comp"]["socket"] = [ (95 - 0) * 0.5, (155) * 0.5, 62 * 0.5]

# ------------------------------------------------------------- skill bar, draught slot, candles, moth, panel
sk = crop(110, 524, 1178, 773)
slots = dark(sk) & (sk[..., :3].max(2) < 40)
lab, n = nd.label(slots)
rects = []
for i, s in enumerate(nd.find_objects(lab)):
    w, h = s[1].stop - s[1].start, s[0].stop - s[0].start
    if 120 < w < 300 and h > 120:
        rects.append([s[1].start * 0.5, s[0].start * 0.5, w * 0.5, h * 0.5])
rects.sort()
meta["skillbar"] = {"size": save("skillbar", sk), "slots": rects}
dr = crop(1178, 552, 1398, 764)
meta["slot_draught"] = {"size": save("slot_draught", dr)}
cand = crop(1492, 546, 2478, 782)
cw = cand.shape[1] / 6
save("candle_lit", cand[:, int(cw * 0):int(cw * 1)])
save("candle_out", cand[:, int(cw * 4):int(cw * 5)])
save("moth", crop(1619, 1095, 1914, 1389))
pn = crop(1941, 1159, 2447, 1371)
meta["panel"] = {"size": save("panel", pn, 1.0)}
json.dump(meta, open(f"{OUT}/ui.json", "w"), indent=1)
print(json.dumps(meta, indent=1))
