"""Turn DorkTeach's concept sheets (Art/*.jpg) into game sprites.

Cuts each subject off the flat background, scales it to game size at 4x
density (shown at scale 0.25), writes a normal map for 2D lighting and
records feet / facing in assets/hd.json.
"""
import json, sys, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as nd

SRC = sys.argv[1]          # folder with img0..img7.jpg
OUT = sys.argv[2]          # project assets folder
sys.path.insert(0, os.path.dirname(__file__))
from props3 import normal_from


def cutout(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    b = np.concatenate([a[:16].reshape(-1, 3), a[-16:].reshape(-1, 3), a[:, :16].reshape(-1, 3), a[:, -16:].reshape(-1, 3)])
    bg = np.median(b, 0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    lab, n = nd.label(d < 14)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    sizes = nd.sum(np.ones_like(d), lab, index=np.arange(n + 1))
    means = nd.mean(d, lab, index=np.arange(n + 1))
    pockets = [k for k in range(1, n + 1) if k not in border and sizes[k] > 900 and means[k] < 6.5]
    bgmask = np.isin(lab, list(border) + pockets)
    alpha = np.where(bgmask, np.clip((d - 8) / 40, 0, 1) ** 1.5, 1.0)
    am = np.maximum(alpha, 1e-3)[..., None]
    fg = np.clip((a - (1 - am) * bg) / am, 0, 255)
    comp, _ = nd.label(nd.binary_dilation(alpha > 0.35, iterations=14))
    boxes = []
    for i, s in enumerate(nd.find_objects(comp)):
        y0, y1, x0, x1 = s[0].start, s[0].stop, s[1].start, s[1].stop
        if (y1 - y0) * (x1 - x0) > 60 * 60:
            boxes.append((x0, y0, x1, y1, i + 1))
    boxes.sort(key=lambda r: (r[1] // 150, r[0]))
    return fg, alpha, comp, boxes


def piece(cut, k, merge=()):
    """RGBA crop of component k (plus any merged components), masked to its own shape."""
    fg, alpha, comp, boxes = cut
    ids = [boxes[k][4]] + [boxes[m][4] for m in merge]
    mask = np.isin(comp, ids)
    xs = [boxes[i][0] for i in [k, *merge]]; ys = [boxes[i][1] for i in [k, *merge]]
    xe = [boxes[i][2] for i in [k, *merge]]; ye = [boxes[i][3] for i in [k, *merge]]
    x0, y0, x1, y1 = min(xs), min(ys), max(xe), max(ye)
    a = alpha * mask
    rgba = np.dstack([fg, a * 255])[y0:y1, x0:x1]
    return rgba


def tight(rgba):
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fig_h(rgba):
    ys, _ = np.nonzero(rgba[..., 3] > 128)
    return ys.max() - ys.min() + 1


def resize(rgba, f):
    h, w = rgba.shape[:2]
    nw, nh = max(1, round(w * f)), max(1, round(h * f))
    a = rgba[..., 3:4] / 255.0
    pre = Image.fromarray(np.clip(rgba[..., :3] * a, 0, 255).astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
    al = Image.fromarray(rgba[..., 3].astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
    pre = np.asarray(pre).astype(np.float32); al = np.asarray(al).astype(np.float32)
    rgb = np.clip(pre / np.maximum(al[..., None] / 255.0, 1e-3), 0, 255)
    out = np.dstack([rgb, al]).astype(np.uint8)
    out = np.pad(out, ((4, 4), (4, 4), (0, 0)))
    im = Image.fromarray(out, 'RGBA')
    # light sharpen so the pixel-art detail survives the downscale
    sharp = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=70, threshold=2))
    return sharp


def feet(im):
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 128)
    bottom = ys.max()
    band = ys > bottom - max(3, (bottom - ys.min()) * 0.08)
    return [float(np.median(xs[band])), float(bottom - 1)]


cuts = {i: cutout(f'{SRC}/img{i}.jpg') for i in range(8)}  # first batch: img0..img7; second batch: new0..new7
manifest = {"characters": {}, "portraits": {}, "icons": [], "props": {}}


def quad(cut, qx, qy, largest=False):
    """Everything in one quarter of a 2x2 pose sheet (keeps sparks, smoke and arrows with the pose)."""
    fg, alpha, comp, boxes = cut
    H, W = alpha.shape
    # components whose bulk sits in this quarter (a component can't be shared)
    yy, xx = np.mgrid[0:H, 0:W]
    inq = (xx // (W // 2) == qx) & (yy // (H // 2) == qy)
    ids = []
    for b in boxes:
        c = comp == b[4]
        if (c & inq).sum() > 0.5 * c.sum():
            ids.append(b[4])
    near = (xx >= qx * W // 2 - 24) & (xx < (qx + 1) * W // 2 + 24) & (yy >= qy * H // 2 - 24) & (yy < (qy + 1) * H // 2 + 24)
    if largest and ids:
        ids = [max(ids, key=lambda i: (comp == i).sum())]
    mask = (np.isin(comp, ids) & near) if ids else inq
    rgba = np.dstack([fg, alpha * mask * 255])
    return tight(rgba)


# hero pose sheets (front, walk, back, attack) and target heights in screen px
HEROES = {"sael": ("new0", 31, {"idle": (0, 0, 1), "walk0": (1, 0, 1), "back": (0, 1, 1), "strike": (1, 1, 1)}),
          "puck": ("new1", 32, {"idle": (0, 0, -1), "walk0": (1, 0, 1), "back": (0, 1, 1), "strike": (1, 1, 1)}),
          "average": ("new6", 37, {"idle": (0, 0, 1), "walk0": (1, 0, 1), "back": (0, 1, 1), "strike": (1, 1, 1)}),
          "brokk": ("new7", 29, {"idle": (0, 0, 1), "walk0": (1, 0, 1), "back": (0, 1, 1), "strike": (1, 1, 1)})}
for hid, (img, target, poses) in HEROES.items():
    cut = cutout(f'{SRC}/{img}.jpg')
    raw = {p: quad(cut, q[0], q[1]) for p, q in poses.items()}
    f = target * 4.0 / fig_h(raw["idle"])
    meta = {"scale": 0.25, "poses": {}}
    for p, q in poses.items():
        im = resize(raw[p], f)
        name = f"hd_{hid}_{p}"
        im.save(f"{OUT}/{name}.png")
        normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/{name}_n.png")
        meta["poses"][p] = {"tex": name, "foot": feet(im), "w": im.width, "h": im.height, "faces": q[2]}
    meta["poses"]["cast"] = meta["poses"]["strike"]
    manifest["characters"][hid] = meta
    print(hid, {p: (v["w"], v["h"]) for p, v in meta["poses"].items()})

# extra pose sheets (third batch): hurt / dodge / kneel / dead, back views, casts.
# Each sheet is scaled so its reference pose matches the size already used in game.
EXTRA = {
    # id: (image, {pose: (qx, qy, faces, largest)}, reference pose, height of the reference pose relative to idle)
    "puck": ("b3_0", {"hurt": (0, 0, 1, 0), "dodge": (1, 0, 1, 0), "drink": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "hurt", 0.97),
    "sael": ("b3_1", {"hurt": (0, 0, 1, 0), "dodge": (1, 0, 1, 0), "drink": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "hurt", 0.97),
    "average": ("b3_2", {"hurt": (0, 0, 1, 0), "dodge": (1, 0, 1, 0), "drink": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "hurt", 0.97),
    "brokk": ("b3_3", {"hurt": (0, 0, 1, 0), "dodge": (1, 0, 1, 0), "drink": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "hurt", 0.97),
    "brute": ("b3_4", {"hurt": (1, 0, 1, 0), "fall": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "hurt", 1.0),
    "ghoul": ("b3_4", {"fall": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "fall", 0.72),
    "iron_brother": ("b3_5", {"back": (0, 0, 1, 0), "slam": (1, 0, 1, 0), "hurt": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "back", 1.0),
}
NEW_IDS = {
    # brand-new sheets that define a character from scratch: id: (image, target height, poses, reference)
    "moth_horror": ("b3_6", 38, {"idle": (0, 0, 1, 0), "cast": (1, 0, 1, 0), "hurt": (0, 1, 1, 0), "dead": (1, 1, 1, 0)}, "idle"),
    "cultist": ("b3_7", 32, {"idle": (0, 0, 1, 0), "walk0": (1, 0, 1, 0), "back": (0, 1, 1, 0), "cast": (1, 1, 1, 0)}, "idle"),
}


def add_poses(cid, img, poses, f):
    cut = cutout(f'{SRC}/{img}.jpg')
    meta = manifest["characters"].setdefault(cid, {"scale": 0.25, "poses": {}})
    raw = {p: quad(cut, q[0], q[1], bool(q[3])) for p, q in poses.items()}
    for p, q in poses.items():
        im = resize(raw[p], f(raw))
        name = f"hd_{cid}_{p}"
        im.save(f"{OUT}/{name}.png")
        normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/{name}_n.png")
        meta["poses"][p] = {"tex": name, "foot": feet(im), "w": im.width, "h": im.height, "faces": q[2]}
    print(cid, sorted(meta["poses"]))


# single-image bosses (Act II): the whole subject, largest component plus anything attached
SINGLE = {"mirror_wraith": ("b3_20", 58), "shadow_moth": ("b3_21", 62), "dragon": ("b3_19", 112)}


def add_single(cid, img, target):
    cut = cutout(f'{SRC}/{img}.jpg')
    fg, alpha, comp, boxes = cut
    big = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
    raw = tight(piece(cut, boxes.index(big)))
    im = resize(raw, target * 4.0 / fig_h(raw))
    name = f"hd_{cid}_idle"
    im.save(f"{OUT}/{name}.png")
    normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/{name}_n.png")
    manifest["characters"][cid] = {"scale": 0.25, "poses": {"idle": {"tex": name, "foot": feet(im), "w": im.width, "h": im.height, "faces": 1}}}
    print(cid, im.size)


# Puck's standing pose in new1 has loose short hair; he wears the long ponytail everywhere else,
# so he stands in his walking frame until a long-haired idle is painted.
IDLE_FROM = {}   # (Puck has a long-haired front pose since the fourth batch)

# fourth batch (c4_*): full pose sheets in the newest style. Each sheet's first entry with an
# idle sets the scale (same target height as before); sheets without one reuse that scale.
C4 = {
    "puck": [("c4_0", {"idle": (0, 0, 1), "walk0": (1, 0, 1), "back": (0, 1, 1), "strike": (1, 1, 1)}),
             ("c4_1", {"walk1": (1, 0, 1)}),
             # the sprint frames play when he dashes
             ("c4_2", {"run0": (0, 0, 1), "run1": (1, 0, 1), "windup": (0, 1, 1), "cast": (1, 1, 1)})],
    "average": [("c4_3", {"idle": (0, 0, 1), "back": (1, 0, 1), "windup": (0, 1, -1), "strike": (1, 1, 1)})],
    "brokk": [("c4_4", {"idle": (0, 0, 1), "back": (1, 0, 1), "strike": (0, 1, 1), "dodge": (1, 1, 1)})],
    "sael": [("c4_5", {"idle": (0, 0, 1), "back": (1, 0, 1), "walk0": (0, 1, -1), "walk1": (1, 1, -1)})],
}
C4_TARGET = {"puck": 32, "average": 37, "brokk": 29, "sael": 31}


def add_c4():
    for cid, sheets in C4.items():
        if not all(os.path.exists(f"{SRC}/{img}.jpg") for img, _ in sheets):
            continue
        meta = manifest["characters"].setdefault(cid, {"scale": 0.25, "poses": {}})
        f = None
        for img, poses in sheets:
            cut = cutout(f"{SRC}/{img}.jpg")
            raw = {p: quad(cut, q[0], q[1], True) for p, q in poses.items()}
            if "idle" in raw:
                f = C4_TARGET[cid] * 4.0 / fig_h(raw["idle"])
            for p, q in poses.items():
                im = resize(raw[p], f)
                name = f"hd_{cid}_{p}"
                im.save(f"{OUT}/{name}.png")
                normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/{name}_n.png")
                meta["poses"][p] = {"tex": name, "foot": feet(im), "w": im.width, "h": im.height, "faces": q[2]}
        if "cast" not in [p for _, ps in sheets for p in ps]:
            meta["poses"]["cast"] = meta["poses"]["strike"]
        print("c4", cid, sorted(meta["poses"].keys()))


def finish_characters():
    for cid, src in IDLE_FROM.items():
        if cid in manifest["characters"] and src in manifest["characters"][cid]["poses"]:
            manifest["characters"][cid]["poses"]["idle"] = dict(manifest["characters"][cid]["poses"][src])
    for cid, (img, target) in SINGLE.items():
        add_single(cid, img, target)
    for cid, (img, target, poses, ref) in NEW_IDS.items():
        manifest["characters"][cid] = {"scale": 0.25, "poses": {}}
        add_poses(cid, img, poses, lambda raw, t=target, r=ref: t * 4.0 / fig_h(raw[r]))
        manifest["characters"][cid]["poses"]["strike"] = manifest["characters"][cid]["poses"]["cast"]
    for cid, (img, poses, ref, rel) in EXTRA.items():
        idle_h = manifest["characters"][cid]["poses"]["idle"]["h"] - 8  # padded image height ~ figure height
        add_poses(cid, img, poses, lambda raw, h=idle_h, r=ref, k=rel: h * k / fig_h(raw[r]))
    add_c4()


# framed portraits: keep the frame for big use, crop the face for small slots
PORTRAITS = {"puck": ("new2", (0.13, 0.12, 0.87, 0.86)), "sael": ("new3", (0.09, 0.08, 0.92, 0.91)),
             "average": ("new4", (0.09, 0.08, 0.92, 0.91)), "brokk": ("new5", (0.09, 0.08, 0.92, 0.91))}
for hid, (img, (l, t, r, b)) in PORTRAITS.items():
    im = Image.open(f"{SRC}/{img}.jpg").convert("RGB")
    W, H = im.size
    im.resize((128, 128), Image.LANCZOS).save(f"{OUT}/portrait_{hid}_framed.png")
    inner = im.crop((int(l * W), int(t * H), int(r * W), int(b * H)))
    iw, ih = inner.size
    face = inner.crop((int(iw * 0.14), int(ih * 0.02), int(iw * 0.86), int(ih * 0.74)))
    face.resize((96, 96), Image.LANCZOS).save(f"{OUT}/portrait_{hid}.png")
    manifest["portraits"][hid] = f"portrait_{hid}"

# Nana, cut from the first Puck concept (she was painted behind him)
fg, alpha, comp, boxes = cuts[7]
x0, y0, x1, y1 = 1150, 160, 1760, 1000
f_ = fg[y0:y1, x0:x1]; a_ = alpha[y0:y1, x0:x1]
mx = f_.max(2); mn = f_.min(2); sat = (mx - mn) / np.maximum(mx, 1)
lab, n = nd.label(nd.binary_closing((sat < 0.2) & (mx > 60), iterations=3))
sizes = nd.sum(np.ones_like(lab), lab, range(n + 1))
m = nd.binary_dilation(nd.binary_fill_holes(lab == int(np.argmax(sizes[1:])) + 1), iterations=2)
hh, ww = m.shape
fade = np.clip(np.linspace(1.6, -0.2, hh), 0, 1)[:, None] * np.clip(np.linspace(0, 6, ww), 0, 1)[None, :]
nana = tight(np.dstack([f_, a_ * m * fade * 255]))
resize(nana, 130.0 / nana.shape[0]).save(f"{OUT}/prop_nana.png")

# ------------------------------------------------------------------ characters
# id: (image, target figure height in screen px, [(pose, component, faces, merge)], reference pose)
CH = {
    "ghoul":   (3, 24, [("idle", 2, 1, ()), ("walk0", 3, 1, ()), ("walk1", 9, 1, ()), ("walk2", 10, 1, ()),
                        ("windup", 12, 1, ()), ("strike", 4, 1, ())], "idle"),
    "brute":   (3, 40, [("idle", 0, 1, ()), ("walk0", 8, 1, ()), ("strike", 11, 1, ())], "each"),
    "iron_brother": (3, 80, [("idle", 6, 1, ()), ("walk0", 7, 1, ()), ("walk1", 14, 1, ()), ("windup", 14, 1, ()), ("strike", 15, -1, ())], "idle"),
}
for cid, (img, target, poses, ref) in CH.items():
    cut = cuts[img]
    raw = {p: tight(piece(cut, k, merge)) for p, k, _, merge in poses}
    meta = {"scale": 0.25, "poses": {}}
    for p, k, faces, merge in poses:
        f = target * 4.0 / fig_h(raw[p if ref == "each" else ref])
        im = resize(raw[p], f)
        name = f"hd_{cid}_{p}"
        im.save(f"{OUT}/{name}.png")
        normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/{name}_n.png")
        meta["poses"][p] = {"tex": name, "foot": feet(im), "w": im.width, "h": im.height, "faces": faces}
    manifest["characters"][cid] = meta
    print(cid, {p: (v["w"], v["h"]) for p, v in meta["poses"].items()})

finish_characters()

# ------------------------------------------------------------------ item icons
ICONS = ["rapier", "shuriken", "grudge_book", "dreamleaf", "gigglecap", "draught", "rune", "storm_quiver", "greataxe"]
cut = cuts[0]
grid = sorted(range(len(cut[3])), key=lambda i: (round(cut[3][i][1] / 300), cut[3][i][0]))
for k, name in enumerate(ICONS):
    rgba = tight(piece(cut, grid[k]))
    f = 56.0 / max(rgba.shape[:2])
    im = resize(rgba, f)
    canvas = Image.new("RGBA", (64, 64))
    canvas.alpha_composite(im, ((64 - im.width) // 2, (64 - im.height) // 2))
    canvas.save(f"{OUT}/icon_{name}.png")
    manifest["icons"].append(name)

# ------------------------------------------------------------------ props (replace in place, anchored at the base)
PROPS = {"moth_shrine": (1, 0, 52), "gibbet": (1, 1, 50), "brazier": (1, 2, 24), "fern": (1, 3, 16), "rift": (2, 1, 56)}
# third batch: one pine in four sizes, the chapel ruin, the gate (closed | open)
PROPS_B3 = {"pine_0": ("b3_13", 0, ("h", 88)), "pine_1": ("b3_13", 0, ("h", 98)), "pine_2": ("b3_13", 0, ("h", 110)), "pine_3": ("b3_13", 0, ("h", 92)),
            "ruin_wall_0": ("b3_14", 0, ("w", 58)), "ruin_wall_1": ("b3_14", 0, ("w", 52)), "ruin_wall_2": ("b3_14", 0, ("w", 64)),
            "gate_closed": ("b3_15", 0, ("w", 50)), "gate_open": ("b3_15", 1, ("w", 50))}
for pid, (img, k, target) in PROPS.items():
    rgba = tight(piece(cuts[img], k))
    im = resize(rgba, target * 4.0 / rgba.shape[0])
    if pid == "brazier":
        # three flicker frames: brighten / dim the fire pixels
        arr = np.asarray(im).astype(np.float32)
        fire = (arr[..., 0] > 170) & (arr[..., 0] > arr[..., 2] * 1.6) & (arr[..., 3] > 0)
        for fi, g in enumerate([1.0, 1.15, 0.88]):
            fr = arr.copy()
            fr[fire, :3] = np.clip(fr[fire, :3] * g, 0, 255)
            Image.fromarray(fr.astype(np.uint8)).save(f"{OUT}/prop_brazier_{fi}.png")
        manifest["props"]["brazier"] = {"w": im.width, "h": im.height, "frames": 3}
        continue
    im.save(f"{OUT}/prop_{pid}.png")
    normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/prop_{pid}_n.png")
    manifest["props"][pid] = {"w": im.width, "h": im.height}
b3_cuts = {}
for pid, (img, k, (axis, size)) in PROPS_B3.items():
    if img not in b3_cuts:
        b3_cuts[img] = cutout(f"{SRC}/{img}.jpg")
    rgba = tight(piece(b3_cuts[img], k))
    if pid.startswith("pine"):
        # the painted tree touches the top of the image: grow a tapered tip and fade the flat cut into it
        rgba = rgba.copy()
        hh, ww = rgba.shape[:2]
        a = rgba[..., 3]
        top_row = np.nonzero(a[0] > 100)[0]
        cx = int(top_row.mean()) if len(top_row) else ww // 2
        half0 = (top_row.max() - top_row.min()) / 2 if len(top_row) else 20
        tip = int(hh * 0.10)
        ext = np.zeros((tip, ww, 4), np.float32)
        top = rgba[:40]
        needle = np.median(top[top[..., 3] > 220][:, :3], 0)   # the tree's own needle colour
        rng = np.random.default_rng(7)
        for y in range(tip):
            half = half0 * (y / tip) ** 1.3
            x0, x1 = int(cx - half), int(cx + half) + 1
            n = max(1, x1 - x0)
            shade = (0.7 + 0.3 * np.cos(np.linspace(-1.4, 1.4, n)))[:, None] * (0.85 + 0.3 * rng.random((n, 1)))
            ext[y, x0:x1, :3] = needle * shade
            ext[y, x0:x1, 3] = 255
            if n > 2:   # dark outline like the painted needles
                ext[y, x0, :3] = needle * 0.35
                ext[y, x1 - 1, :3] = needle * 0.35
        rgba = np.concatenate([ext, rgba], 0)
    im = resize(rgba, size * 4.0 / (rgba.shape[0] if axis == "h" else rgba.shape[1]))
    im.save(f"{OUT}/prop_{pid}.png")
    normal_from(im, strength=2.0, bevel=4).save(f"{OUT}/prop_{pid}_n.png")
    manifest["props"][pid] = {"w": im.width, "h": im.height}

json.dump(manifest, open(f"{OUT}/hd.json", "w"), indent=1)
print("done")
