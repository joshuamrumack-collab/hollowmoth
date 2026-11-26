"""Cut DorkTeach's second UI batch into game pieces.

  python tools/artgen/import_ui2.py <dir with the three sheets>

  Dialogue and menu.jpg -> ui/dlg_box, dlg_moth, menu_panel, menu_bar, card, slider_track, slider_knob, check_on/off/x
  Inventory.jpg         -> ui/inv_panel, inv_bag, inv_cell, inv_slot + item icons (icon_item_*.png)
  Sigil socketing.jpg   -> ui/sigil_panel + sigil stones (sigil_*.png)
Coordinates are for the 2752x1536 sheets.
"""
import json, os, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "Art"
OUT = "assets/"
UI = OUT + "ui/"
rng = np.random.default_rng(3)


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGB")


def key_dark(im, bg, soft=60.0):
    """Alpha from distance to the sheet's dark background (keeps glows soft)."""
    a = np.asarray(im).astype(np.float32)
    al = np.clip(np.clip(a - bg, 0, None).max(2) / soft, 0, 1)
    rgb = np.clip((a - bg * (1 - al[..., None])) / np.maximum(al[..., None], 1e-3), 0, 255)
    return Image.fromarray(np.dstack([rgb, al * 255]).astype(np.uint8), "RGBA")


def solid_mask(a, bg, thr):
    """Everything inside the outline of what differs from the background (holes filled)."""
    from scipy import ndimage
    m = np.abs(a - bg).max(2) > thr
    m = ndimage.binary_closing(m, iterations=3)
    m = ndimage.binary_fill_holes(m)
    m = ndimage.binary_opening(m, iterations=2)
    return ndimage.gaussian_filter(m.astype(np.float32), 0.8)


def cut_frame(im, box, bg, thr=16.0):
    """A frame on the sheet background: crop, keep everything inside its outline."""
    a = np.asarray(im.crop(box)).astype(np.float32)
    al = solid_mask(a, bg, thr)
    return Image.fromarray(np.dstack([a, al * 255]).astype(np.uint8), "RGBA")


def cut_glow(im, box, bg, thr=30.0, soft=45.0):
    """A solid object with a soft glow around it (sigil stones)."""
    a = np.asarray(im.crop(box)).astype(np.float32)
    core = solid_mask(a, bg, thr)
    glow = np.clip(np.clip(a - bg, 0, None).max(2) / soft, 0, 1)
    al = np.maximum(core, glow)
    rgb = np.clip((a - bg * (1 - al[..., None])) / np.maximum(al[..., None], 1e-3), 0, 255)
    return Image.fromarray(np.dstack([rgb, al * 255]).astype(np.uint8), "RGBA")


def blank(im, box, sample_box=None, noise=4.0):
    """Paint over a region with the median colour of a sample (plus a little grain)."""
    a = np.asarray(im).astype(np.float32).copy()
    sb = sample_box or box
    col = np.median(a[sb[1]:sb[3], sb[0]:sb[2]].reshape(-1, 3), 0)
    h, w = box[3] - box[1], box[2] - box[0]
    a[box[1]:box[3], box[0]:box[2]] = col + rng.normal(0, noise, (h, w, 1))
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def patch_from(im, dst, dx):
    """Copy a same-sized patch from dx pixels to the side over dst (to remove a detail)."""
    p = im.crop((dst[0] + dx, dst[1], dst[2] + dx, dst[3]))
    im = im.copy()
    im.paste(p, (dst[0], dst[1]))
    return im


def save(im, path, h=None, w=None):
    """Save, downsized to roughly 4x HUD density (the HUD is 480x270, the screen 1920x1080)."""
    if w:
        h = max(1, round(im.height * w / im.width))
    if h:
        im = im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)
    im.save(path)
    return im.size


def frac(r, box):
    """A rectangle inside a cut piece, as fractions of the piece (survives resizing)."""
    W, H = box[2] - box[0], box[3] - box[1]
    return [round((r[0] - box[0]) / W, 4), round((r[1] - box[1]) / H, 4), round((r[2] - box[0]) / W, 4), round((r[3] - box[1]) / H, 4)]


meta = {}
os.makedirs(UI, exist_ok=True)

# ---------------- dialogue + menus
s = load("Dialogue and menu.jpg")
bg = np.array([27.0, 28.0, 32.0])
d = patch_from(s, (2400, 345, 2565, 495), -260)                    # remove the moth glyph
d = blank(d, (170, 158, 540, 524), (176, 160, 186, 170), 2.0)      # empty the portrait well
box = (112, 50, 2640, 580)
meta["dlg_box"] = {"size": list(save(cut_frame(d, box, bg), UI + "dlg_box.png", w=1840)),
                   "well": frac((170, 158, 540, 524), box), "text": frac((600, 175, 2585, 505), box)}
save(key_dark(s.crop((2400, 345, 2565, 495)), bg, 50.0), UI + "dlg_moth.png", 48)
# menu panel with candles and the moth; the four bars come out as one reusable bar
m = blank(s, (200, 900, 1056, 1405), (205, 1395, 1050, 1405), 3.0)
box = (60, 600, 1140, 1490)
meta["menu_panel"] = {"size": list(save(cut_frame(m, box, bg), UI + "menu_panel.png", w=800)), "inner": frac((200, 900, 1056, 1405), box)}
meta["menu_bar"] = {"size": list(save(s.crop((242, 916, 1014, 1026)), UI + "menu_bar.png", w=600))}
# bone-sealed card (feat cards)
box = (1405, 655, 2006, 1488)
meta["card"] = {"size": list(save(cut_frame(s, box, bg), UI + "card.png", w=360))}
# options: slider + checkboxes
tr = patch_from(s, (2300, 735, 2380, 797), -150)
save(cut_frame(tr, (2075, 730, 2614, 802), bg), UI + "slider_track.png", w=480)
save(cut_frame(s, (2318, 728, 2362, 804), bg), UI + "slider_knob.png", h=68)
for nm, b in [("check_on", (2076, 1102, 2178, 1203)), ("check_x", (2077, 1216, 2177, 1317)), ("check_off", (2077, 1326, 2173, 1425))]:
    save(cut_frame(s, b, bg), UI + nm + ".png", h=48)

# ---------------- inventory
s = load("Inventory.jpg")
bg = np.array([25.0, 26.0, 30.0])
p = blank(s, (106, 94, 1276, 1444), (500, 1420, 900, 1440), 3.0)
box = (40, 28, 1346, 1520)
meta["inv_panel"] = {"size": list(save(cut_frame(p, box, bg), UI + "inv_panel.png", h=960)), "inner": frac((106, 94, 1276, 1444), box)}
COLS = [1638, 1796, 1955, 2116, 2274, 2435]
ROWS = [159, 309, 464, 621, 779, 939, 1099, 1259]
# the bag: keep the frame, wipe the grid off the board
b = blank(s, (1562, 112, 2640, 1450), (1566, 500, 1622, 900), 4.0)
box = (1496, 32, 2712, 1520)
meta["inv_bag"] = {"size": list(save(cut_frame(b, box, bg), UI + "inv_bag.png", h=960)), "inner": frac((1562, 112, 2640, 1450), box)}
save(s.crop((1636, 307, 1782, 455)), UI + "inv_cell.png", h=100)
sl = blank(s, (191, 660, 343, 811), (196, 664, 206, 674), 2.0)
save(sl.crop((158, 622, 376, 840)), UI + "inv_slot.png", h=128)


def cell(c, r, inset=14):
    return s.crop((COLS[c] + inset, ROWS[r] + inset, COLS[c] + 142 - inset, ROWS[r] + 142 - inset))


def frame_in(box, inset=26):
    return s.crop((box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset))


icons = {
    "book": cell(0, 0), "shuriken": cell(1, 0), "mushroom": cell(2, 2), "leaf": cell(0, 3), "axe": cell(5, 3),
    "rune": cell(0, 4), "quiver": cell(4, 4), "mace": cell(2, 5), "plate": cell(3, 5), "gauntlet": cell(4, 5),
    "potion": cell(5, 5), "sword": cell(1, 6), "leather": cell(2, 6), "herb": cell(3, 6), "keys": cell(4, 6),
    "scroll": cell(5, 6), "helm": frame_in((578, 124, 780, 338)), "amulet": frame_in((814, 174, 962, 334), 18),
    "cloak": frame_in((166, 330, 370, 598)), "cuirass": frame_in((166, 630, 370, 838)), "belt": frame_in((166, 870, 370, 1078)),
    "gloves": frame_in((986, 630, 1192, 838)), "boots": frame_in((986, 870, 1192, 1078)), "ring": frame_in((842, 864, 962, 998), 16),
    "rapier": frame_in((166, 1114, 370, 1394)), "pouch": frame_in((396, 1194, 570, 1390), 20), "shield": frame_in((598, 1194, 778, 1390), 20),
}
for nm, im in icons.items():
    w, h = im.size
    q = max(w, h)
    sq = Image.new("RGB", (q, q), im.getpixel((2, 2)))
    sq.paste(im, ((q - w) // 2, (q - h) // 2))
    sq.resize((96, 96), Image.LANCZOS).save(OUT + "icon_item_%s.png" % nm)

# ---------------- sigils
s = load("Sigil socketing.jpg")
bg = np.array([24.0, 27.0, 32.0])
pn = blank(s, (440, 388, 962, 938), (450, 395, 470, 415), 2.0)
box = (100, 30, 1300, 1495)
meta["sigil_panel"] = {"size": list(save(cut_frame(pn, box, bg), UI + "sigil_panel.png", h=920)),
                       "window": frac((440, 388, 962, 938), box),
                       "sockets": [frac((x - 48, 1083, x + 48, 1179), box) for x in (494, 626, 760, 894)],
                       "plate": frac((514, 1321, 884, 1431), box)}
SIG = ["moth", "eye", "star", "fire", "skull", "moon", "chain", "lightning", "thorn"]
XS = [(1395, 1797), (1834, 2229), (2271, 2665)]
YS = [(70, 538), (546, 1013), (1022, 1489)]
for i, nm in enumerate(SIG):
    x, y = XS[i % 3], YS[i // 3]
    save(cut_glow(s, (x[0], y[0], x[1], y[1]), bg), OUT + "sigil_%s.png" % nm, 96)

old = json.load(open(UI + "ui.json")) if os.path.exists(UI + "ui.json") else {}
old.update(meta)
json.dump(old, open(UI + "ui.json", "w"), indent=1)
print("ui2 imported:", ", ".join(meta))
