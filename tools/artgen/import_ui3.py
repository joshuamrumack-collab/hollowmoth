"""Cut DorkTeach's third batch: the shrine/level-up screens, the camp NPCs, their stations and portraits.

  python tools/artgen/import_ui3.py <dir with the sheets>

  moth shrine and level up.jpg -> ui/lvl_panel, ui/shrine_panel
  town hub.jpg                 -> prop_npc_smith / _alchemist / _gambler, prop_stash
  town hub stations.jpg        -> prop_station_forge / _alchemy / _dice / _cookfire
  <name> portrait.jpg          -> portrait_<id>_framed (128) + portrait_<id> (96)
"""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from import_ui2 import solid_mask, blank, frac, save  # noqa: E402  (re-uses the second batch's helpers)

SRC = sys.argv[1] if len(sys.argv) > 1 else "Art"
OUT = "assets/"
UI = OUT + "ui/"


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGB")


def cut_solid(im, box, bg, thr=30.0, max_hole=2500):
    """Key out the background, filling only small holes (so gaps between a rack's poles stay open)."""
    from scipy import ndimage
    a = np.asarray(im.crop(box)).astype(np.float32)
    dist = np.abs(a - bg).max(2)
    m = dist > thr
    m = ndimage.binary_closing(m, iterations=2)
    holes = ndimage.binary_fill_holes(m) & ~m
    lab, n = ndimage.label(holes)
    if n:
        idx = range(1, n + 1)
        sizes = ndimage.sum(holes, lab, idx)
        # a hole stays open only if it is big and really the sheet's background colour
        bgness = ndimage.mean((dist < 9).astype(np.float32), lab, idx)
        fill = [i + 1 for i in range(n) if sizes[i] < max_hole or bgness[i] < 0.7]
        m = m | np.isin(lab, fill)
    m = ndimage.binary_opening(m, iterations=2)
    # drop specks: keep components bigger than 1% of the largest
    lab, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        m = np.isin(lab, np.nonzero(sizes > sizes.max() * 0.01)[0] + 1)
    al = ndimage.gaussian_filter(m.astype(np.float32), 0.8)
    rgba = Image.fromarray(np.dstack([a, al * 255]).astype(np.uint8), "RGBA")
    return rgba.crop(rgba.getbbox())


meta = {}
# ---------------- shrine + level up
s = load("moth shrine and level up.jpg")
bg = np.array([27.0, 28.0, 32.0])
p = blank(s, (176, 164, 532, 518), (180, 168, 190, 178), 2.0)                       # portrait well
for b in [(716, 244, 1215, 307), (716, 370, 1215, 432)]:                             # bar insides
    p = blank(p, b, (1180, 250, 1210, 300), 2.0)
box = (112, 96, 1342, 1480)
meta["lvl_panel"] = {"size": list(save(Image.fromarray(np.dstack([np.asarray(p.crop(box)), solid_mask(np.asarray(p.crop(box)).astype(np.float32), bg, 16.0) * 255]).astype(np.uint8), "RGBA"), UI + "lvl_panel.png", w=760)),
                     "well": frac((176, 164, 532, 518), box), "bar1": frac((716, 244, 1215, 307), box), "bar2": frac((716, 370, 1215, 432), box),
                     "rows": [frac((250, y, 1075, y + 100), box) for y in (614, 758, 882, 1006)],
                     "plus": [frac((1108, y, 1204, y + 100), box) for y in (614, 758, 882, 1006)],
                     "icons": [frac((x - 118, 1140, x + 118, 1376), box) for x in (403, 727, 1052)]}
r = blank(s, (2296, 192, 2398, 274), (2300, 196, 2310, 206), 2.0)                   # the counter
r = blank(r, (1905, 1342, 2414, 1436), (1910, 1346, 1920, 1356), 2.0)               # bottom plate
box = (1664, 60, 2652, 1482)
meta["shrine_panel"] = {"size": list(save(Image.fromarray(np.dstack([np.asarray(r.crop(box)), solid_mask(np.asarray(r.crop(box)).astype(np.float32), bg, 16.0) * 255]).astype(np.uint8), "RGBA"), UI + "shrine_panel.png", w=620)),
                        "count": frac((2296, 192, 2398, 274), box), "plate": frac((1905, 1342, 2414, 1436), box),
                        "rows": [frac((1936, y, 2490, y + 96), box) for y in (464, 590, 717, 845, 973, 1101)]}

# ---------------- camp NPCs and their stations (2x2 sheets)
for sheet, names, heights in [("town hub.jpg", ["npc_smith", "npc_alchemist", "npc_gambler", "stash"], [148, 128, 140, 104]),
                              ("town hub stations.jpg", ["station_forge", "station_alchemy", "station_dice", "station_cookfire"], [260, 210, 190, 170])]:
    s = load(sheet)
    a = np.asarray(s).astype(np.float32)
    bg = np.median(a[:30, :30].reshape(-1, 3), 0)
    H = s.height // 2
    for i, nm in enumerate(names):
        cx, cy = i % 2, i // 2
        im = cut_solid(s, (cx * H, cy * H, (cx + 1) * H, (cy + 1) * H), bg)
        save(im, OUT + "prop_%s.png" % nm, h=heights[i])

# ---------------- portraits
for fname, pid in [("blacksmith portrait.jpg", "smith"), ("alchemist portrait.jpg", "alchemist"), ("gambler portrait.jpg", "gambler")]:
    p = load(fname)
    k = p.width / 1000.0
    p.crop((int(8 * k), int(8 * k), int(992 * k), int(992 * k))).resize((128, 128), Image.LANCZOS).save(OUT + "portrait_%s_framed.png" % pid)
    p.crop((int(90 * k), int(90 * k), int(910 * k), int(910 * k))).resize((96, 96), Image.LANCZOS).save(OUT + "portrait_%s.png" % pid)

old = json.load(open(UI + "ui.json"))
old.update(meta)
json.dump(old, open(UI + "ui.json", "w"), indent=1)
print("ui3 imported:", ", ".join(meta))
