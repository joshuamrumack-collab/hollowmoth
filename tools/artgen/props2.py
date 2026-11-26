"""High-density (2x) props for Hollowmoth.

Re-runs the prop drawings from sprites.py on a scaled canvas (shapes, lines
and ellipses are rasterised at full resolution, so curves and outlines get
finer), draws pines natively at 2x, then adds a fine texture pass.
Shown in Godot at scale 0.5 so they match the 2x character sprites.
"""
import json, math, os, random
import numpy as np
from PIL import Image
import sprites as S

K = 2
OUT = S.OUT
Base = S.Canvas


class HiCanvas(Base):
    def __init__(self, w, h):
        super().__init__(w * K, h * K)
        self.k = K

    def p(self, x, y, c):
        if c is None:
            return
        for dy in range(K):
            for dx in range(K):
                Base.p(self, int(round(x * K)) + dx, int(round(y * K)) + dy, c)

    def rect(self, x, y, w, h, c):
        for yy in range(int(round(y * K)), int(round((y + h) * K))):
            for xx in range(int(round(x * K)), int(round((x + w) * K))):
                Base.p(self, xx, yy, c)

    def line(self, x0, y0, x1, y1, c):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * K) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            Base.p(self, (x0 + (x1 - x0) * t) * K, (y0 + (y1 - y0) * t) * K, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for yy in range(int((cy - ry) * K), int((cy + ry) * K) + 1):
            for xx in range(int((cx - rx) * K), int((cx + rx) * K) + 1):
                fx = (xx / K - cx) / max(rx, 0.5)
                fy = (yy / K - cy) / max(ry, 0.5)
                if fx * fx + fy * fy <= 1.0:
                    Base.p(self, xx, yy, c)

    def clear(self, x, y):
        for dy in range(K):
            for dx in range(K):
                xx, yy = int(x * K) + dx, int(y * K) + dy
                if 0 <= xx < self.w and 0 <= yy < self.h:
                    self.px[xx, yy] = (0, 0, 0, 0)


def detail(img, amp=0.07, seed=1):
    a = np.array(img).astype(np.float32)
    h, w = a.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    n = np.sin(xs * 12.9898 + ys * 78.233 + seed) * 43758.5453
    n = (n - np.floor(n)) - 0.5
    m = a[:, :, 3] > 200
    for c in range(3):
        a[:, :, c][m] = np.clip(a[:, :, c][m] * (1 + n[m] * amp * 2), 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def pine_hi(seed, w, h):
    """Drova-like pine, drawn natively at high density."""
    rnd = random.Random(seed)
    cv = Base(w, h)
    cx = w // 2
    trunk = S.MAT["wood"]
    cv.shaded(cx - 5, h - 34, 10, 32, trunk, 2, 3, 0)
    cv.rect(cx - 5, h - 34, 2, 32, (150, 82, 40, 255))
    for k in range(10):
        cv.p(cx - 3 + rnd.randint(0, 6), h - 32 + rnd.randint(0, 28), trunk[0])
    needles = [S.hexc("0b1a1a"), S.hexc("12282a"), S.hexc("1a3834"), S.hexc("244a40"), S.hexc("326250"), S.hexc("4c7e60")]
    tiers = 8
    tier_space = (h - 40) / tiers
    for t in range(tiers):
        top_y = int(6 + t * tier_space)
        tier_h = int(tier_space * 1.9)
        width = (0.10 + t / tiers * 0.4) * w
        for yy in range(tier_h):
            y = top_y + yy
            if y >= h - 26:
                break
            frac = yy / tier_h
            half = frac * width + 1.5
            # jagged hanging needle tips along the bottom edge
            for xx in range(int(-half) - 2, int(half) + 3):
                rel = xx / max(1.0, half)
                if abs(rel) > 1.0 + rnd.uniform(-0.12, 0.1):
                    continue
                droop = abs(rel) * 3
                if frac > 0.92 and rnd.random() < 0.55:
                    continue
                light = (-rel * 0.7 + (1 - frac) * 0.35 + rnd.uniform(-0.25, 0.25))
                idx = 1 + int(np.clip((light + 0.4) * 3.1, 0, 4))
                if frac > 0.85:
                    idx = max(0, idx - 2)
                cv.p(cx + xx, y + droop * 0.0, needles[idx])
            # needle sprays catching light on the left
            if rnd.random() < 0.7:
                hx = cx - int(half * rnd.uniform(0.35, 0.95))
                cv.p(hx, y, needles[5]); cv.p(hx + 1, y, needles[4])
    return cv


def main():
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(manifest_path))
    manifest["props"] = {}
    S.Canvas_orig = S.Canvas
    props = {}
    for i in range(4):
        props[f"pine_{i}"] = pine_hi(i + 1, (52 + (i % 2) * 8) * K, (88 + (i % 3) * 10) * K)
    S.Canvas = HiCanvas
    try:
        for i in range(2):
            props[f"dead_tree_{i}"] = S.dead_tree(i + 3)
        for i in range(3):
            props[f"rock_{i}"] = rock_hi(i, (26 - i * 4), (18 - i * 3))
        props["standing_stone"] = S.standing_stone()
        props["moth_shrine"] = S.moth_shrine()
        props["gibbet"] = S.gibbet()
        for i in range(3):
            props[f"corpse_{i}"] = S.corpse(i)
        for i in range(3):
            props[f"ruin_wall_{i}"] = S.ruin_wall(i + 1)
        props["thorns"] = S.thorn_barrier()
        props["gate_closed"] = S.gate(False)
        props["gate_open"] = S.gate(True)
        for f in range(4):
            props[f"campfire_{f}"] = S.campfire(f)
        for f in range(3):
            props[f"torch_{f}"] = S.torch(f)
        props.update(S.small_props())
    finally:
        S.Canvas = S.Canvas_orig
    no_outline = {"nana", "moth_0", "moth_1"}
    for name, cv in props.items():
        if name not in no_outline and not name.startswith(("campfire", "torch", "brazier")):
            cv.outline()
        img = cv.img
        if not name.startswith(("campfire", "torch", "brazier", "moth", "nana")):
            img = detail(img, 0.06 if not name.startswith("pine") else 0.03, hash(name) % 97)
        img.save(os.path.join(OUT, "prop_" + name + ".png"))
        manifest["props"][name] = {"w": img.width, "h": img.height, "scale": 0.5}
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    print("props", len(props))


def rock_hi(seed, w, h):
    rnd = random.Random(seed)
    W, H = w * K, h * K
    cv = Base(W, H)
    st = [S.hexc("1e1e22"), S.hexc("2e2e34"), S.hexc("42424a"), S.hexc("5a5a62"), S.hexc("74747c")]
    cx, cy = W / 2, H / 2 + 1
    rx, ry = W / 2 - 2, H / 2 - 2
    for y in range(H):
        for x in range(W):
            fx, fy = (x - cx) / rx, (y - cy) / ry
            d = fx * fx + fy * fy
            if d <= 1.0 + rnd.uniform(-0.05, 0.03):
                nz = math.sqrt(max(0.0, 1 - min(d, 1.0)))
                l = -fx * 0.5 - fy * 0.6 + nz * 0.6 + rnd.uniform(-0.12, 0.12)
                cv.p(x, y, st[int(np.clip((l + 0.6) * 2.6, 0, 4))])
    mo = [S.hexc("24331a"), S.hexc("344a22"), S.hexc("4c6630"), S.hexc("62803a")]
    for i in range(W * 3):
        x = rnd.randint(2, W - 3); y = rnd.randint(1, int(H * 0.5))
        if cv.px[x, y][3]:
            cv.p(x, y, mo[rnd.randint(0, 3)])
    return cv


if __name__ == "__main__":
    main()
