"""Rebuild the Act I ground from DorkTeach's painted ground textures.

Uses the level layout from level.py (areas, paths) and paints:
  forest floor (outside)  -> moss texture, darkened
  clearings and paths     -> muddy forest floor with puddles, moss patches
  the Drowned Chapel      -> cracked flagstones
  the Iron Brother's Pit  -> bone-strewn dirt
Writes ground.png, ground_n.png (normals) and ground_s.png (specular: puddles shine).
usage: python ground_textures.py <folder with mud.jpg moss.jpg flag.jpg bones.jpg> <assets folder>
"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import level as Lv

SRC, OUT = sys.argv[1], sys.argv[2]


def load_tile(name, size, seamless=True):
    im = Image.open(os.path.join(SRC, name)).convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    if seamless == "mirror":
        # structured textures (stones): mirror-tile, so edges meet without ghosting
        a = np.concatenate([a, a[:, ::-1]], 1)
        a = np.concatenate([a, a[::-1]], 0)
    elif seamless:
        # cross-fade with a half-shifted copy so the tile edges disappear
        h, w = a.shape[:2]
        wy = np.sin(np.linspace(0, np.pi, h))[:, None]
        wx = np.sin(np.linspace(0, np.pi, w))[None, :]
        m = (wy * wx) ** 0.6
        a = a * m[..., None] + np.roll(np.roll(a, h // 2, 0), w // 2, 1) * (1 - m[..., None])
    return a


def tiled(tile, shape, off=(0, 0)):
    th, tw = tile.shape[:2]
    reps = (shape[0] // th + 2, shape[1] // tw + 2, 1)
    big = np.tile(tile, reps)
    return big[off[0]:off[0] + shape[0], off[1]:off[1] + shape[1]]


def lum(a):
    return a[..., 0] * 0.3 + a[..., 1] * 0.55 + a[..., 2] * 0.15


def match(a, target):
    return a * (target / max(1.0, lum(a).mean()))


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


xs, ys, inside, path = Lv.walk_field()
shape = xs.shape
ragged = Lv.value_noise(shape, 10 / Lv.TEX, 31) - 0.5
inside = inside + ragged * 16
path = path + ragged * 10
patch = Lv.fbm(shape, 7)

mud = match(tiled(load_tile("mud.jpg", 560), shape), 52)
moss = match(tiled(load_tile("moss.jpg", 480), shape, (130, 70)), 46)
forest = match(tiled(load_tile("moss.jpg", 420), shape, (37, 211)), 19) * np.array([0.85, 1.0, 0.9])
# the chapel floor fits inside one copy of the flagstone painting: centre it on the chapel
_ch = next(a for a in Lv.AREAS if a["id"] == "chapel")
_T = int(720 * getattr(Lv, "S", 1.0))
_cx, _cy = int(_ch["pos"][0] / Lv.TEX), int(_ch["pos"][1] / Lv.TEX)
flag = match(tiled(load_tile("flag.jpg", _T, seamless=False), shape, ((-(_cy - _T // 2)) % _T, (-(_cx - _T // 2)) % _T)), 58)
bones = match(tiled(load_tile("bones.jpg", 560), shape, (90, 40)), 50)

img = forest.copy()
w_in = smooth((inside + 6) / 14)[..., None]
clearing = mud * (1 - smooth((patch - 0.5) / 0.12)[..., None]) + moss * smooth((patch - 0.5) / 0.12)[..., None]
w_path = smooth((path - 2) / 10)[..., None]
clearing = clearing * (1 - w_path) + mud * 1.08 * w_path
img = img * (1 - w_in) + clearing * w_in

A = {a["id"]: a for a in Lv.AREAS}
for aid, tex, frac in [("chapel", flag, 0.78), ("pit", bones, 0.86)]:
    a = A[aid]
    d = np.hypot(xs - a["pos"][0], ys - a["pos"][1])
    w = smooth((a["r"] * frac - d + ragged * 30) / 18)[..., None]
    img = img * (1 - w) + tex * w

# dark rim where the forest begins
rim = smooth((inside + 2) / 10) * (1 - smooth((inside - 8) / 10))
img *= (1 - 0.35 * rim)[..., None]
img = np.clip(img, 0, 255)
Image.fromarray(img.astype(np.uint8), "RGB").save(os.path.join(OUT, "ground.png"))

# normals from the painted shading
h = lum(img) / 255.0
h = np.asarray(Image.fromarray((h * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255.0
gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
nx, ny, nz = -gx * 3.0, gy * 3.0, np.ones_like(h)
L = np.sqrt(nx * nx + ny * ny + nz * nz)
nimg = np.stack([nx / L * 127.5 + 127.5, ny / L * 127.5 + 127.5, nz / L * 127.5 + 127.5], -1).astype(np.uint8)
Image.fromarray(nimg, "RGB").save(os.path.join(OUT, "ground_n.png"))

# specular: the painted puddles (blue-dark) shine, stone a little, moss and forest stay dull
r, g, b = img[..., 0], img[..., 1], img[..., 2]
water = (b > r + 6) & (lum(img) < 70) & (w_in[..., 0] > 0.5)
spec = np.full(shape, 16, np.float32)
spec = np.where(water, 210, spec)
spec = spec * (0.4 + 0.6 * w_in[..., 0])
Image.fromarray(np.stack([spec.astype(np.uint8)] * 3, -1), "RGB").save(os.path.join(OUT, "ground_s.png"))
print("ground", img.shape, "water px", int(water.sum()))
