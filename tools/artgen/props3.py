"""4x-density props + normal maps for Godot 2D lighting.

Native 4x drawings for what the eye lands on most (pines, rocks, grass,
reeds, ferns, mushrooms, flames); the rest are lifted from the 2x set with a
fine detail pass. Every prop also gets a normal map (embossed from its
shading, bevelled at the silhouette) so torches light it from the right side.
Shown in Godot at scale 0.25.
"""
import json, math, os, random
import numpy as np
from PIL import Image, ImageFilter
import sprites as S
import props2 as P2

OUT = S.OUT
K = 4


def hexc(h):
    return S.hexc(h)


def normal_from(img, strength=2.2, bevel=3):
    a = np.array(img).astype(np.float32)
    alpha = a[:, :, 3] / 255.0
    lum = (a[:, :, 0] * 0.3 + a[:, :, 1] * 0.55 + a[:, :, 2] * 0.15) / 255.0
    # height = brightness + a bevel that rises away from the silhouette
    inside = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(bevel))
    h = lum * 0.6 + np.array(inside).astype(np.float32) / 255.0 * 0.8
    h = np.array(Image.fromarray((h * 255).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / L, ny / L, nz / L
    out = np.zeros(a.shape, np.uint8)
    out[:, :, 0] = (nx * 127.5 + 127.5).astype(np.uint8)
    out[:, :, 1] = (ny * 127.5 + 127.5).astype(np.uint8)
    out[:, :, 2] = (nz * 127.5 + 127.5).astype(np.uint8)
    out[:, :, 3] = 255
    out[alpha < 0.05] = (128, 128, 255, 255)
    return Image.fromarray(out, "RGBA")


# ----------------------------------------------------------------- natives
def pine4(seed, w, h):
    rnd = random.Random(seed)
    cv = S.Canvas(w, h)
    cx = w // 2
    k = w / 104.0
    tw = int(8 * k)
    bark = [hexc("1c120c"), hexc("2c1c12"), hexc("3e2a1a"), hexc("56391f"), hexc("8a4e26")]
    for y in range(h - int(46 * k), h - 4):
        for x in range(cx - tw, cx + tw):
            rel = (x - cx) / tw
            l = -rel * 0.9 + rnd.uniform(-0.25, 0.25) + (0.4 if ((y // 3 + x) % 9 == 0) else 0)
            idx = int(np.clip((l + 1) * 2, 0, 3))
            if (y + (x * 7) % 11) % 13 == 0:
                idx = 0
            cv.p(x, y, bark[idx])
        cv.p(cx - tw, y, bark[4]); cv.p(cx - tw + 1, y, bark[4])   # firelit rim
    needles = [hexc("08161a"), hexc("0e2226"), hexc("15302e"), hexc("1d4038"), hexc("285244"), hexc("356650"), hexc("4a7e5c"), hexc("6a9a6a")]
    tiers = 10
    tier_space = (h - 34 * k) / tiers
    for t in range(tiers):
        top_y = int(10 * k + t * tier_space)
        tier_h = int(tier_space * 2.0)
        width = (0.08 + t / tiers * 0.4) * w
        for yy in range(tier_h):
            y = top_y + yy
            if y >= h - int(24 * k):
                break
            frac = yy / tier_h
            half = frac * width + 2
            for xx in range(int(-half) - 3, int(half) + 4):
                rel = xx / max(1.0, half)
                edge = 1.0 + 0.12 * math.sin(xx * 0.9 + t * 3 + yy * 0.3) + rnd.uniform(-0.08, 0.06)
                if abs(rel) > edge:
                    continue
                if frac > 0.9 and rnd.random() < 0.6:
                    continue
                light = -rel * 0.75 + (1 - frac) * 0.45 + rnd.uniform(-0.3, 0.3)
                # needle clumps: diagonal strokes
                if ((xx + yy * 2) % 5 == 0) and rnd.random() < 0.5:
                    light -= 0.35
                idx = int(np.clip((light + 0.55) * 3.3, 0, 6))
                if frac > 0.82:
                    idx = max(0, idx - 3)
                cv.p(cx + xx, y, needles[idx])
            for _ in range(2):
                if rnd.random() < 0.6:
                    hx = cx - int(half * rnd.uniform(0.3, 0.95))
                    cv.p(hx, y, needles[7]); cv.p(hx + 1, y + 1, needles[6])
    return cv


def grass4(seed):
    rnd = random.Random(seed)
    cv = S.Canvas(40, 36)
    cols = [hexc("16220f"), hexc("223216"), hexc("30461e"), hexc("44602a"), hexc("5e783a"), hexc("8a9450")]
    for b in range(14):
        x0 = rnd.uniform(6, 34); hgt = rnd.uniform(12, 32); lean = rnd.uniform(-8, 8)
        for i in range(int(hgt)):
            t = i / hgt
            x = x0 + lean * t * t
            c = cols[min(5, int(t * 4.5) + (1 if x0 < 20 else 0))]
            cv.p(x, 35 - i, c)
            if t < 0.5:
                cv.p(x + 1, 35 - i, cols[max(0, int(t * 4))])
    return cv


def reeds4():
    cv = S.Canvas(40, 64)
    rnd = random.Random(3)
    for k in range(7):
        x0 = 4 + k * 5 + rnd.uniform(-1, 1); h = rnd.uniform(36, 58); lean = rnd.uniform(-5, 5)
        for i in range(int(h)):
            t = i / h
            cv.p(x0 + lean * t * t, 63 - i, hexc("4a5a2a") if t < 0.7 else hexc("6a7a3a"))
        tx, ty = x0 + lean, 63 - h
        for j in range(10):
            cv.p(tx, ty + j, hexc("5a3a20") if j % 3 else hexc("7a5030"))
            cv.p(tx + 1, ty + j, hexc("3e2614"))
    return cv


def fern4():
    cv = S.Canvas(72, 40)
    cols = [hexc("1e3820"), hexc("2c4e2c"), hexc("3e6a3a"), hexc("5a8a4a")]
    for k in range(7):
        a = math.pi + 0.2 + k * (math.pi - 0.4) / 6
        L = 30 + (k % 3) * 4
        for r in range(int(L)):
            t = r / L
            x = 36 + math.cos(a) * r; y = 38 + math.sin(a) * r * 0.75 + t * t * 8
            cv.p(x, y, cols[2 if k % 2 else 1])
            leaf = (1 - t) * 6
            for s in (-1, 1):
                for j in range(int(leaf)):
                    cv.p(x + math.cos(a + s * 1.2) * j, y + math.sin(a + s * 1.2) * j * 0.7, cols[3 if s < 0 else 0] if j > 1 else cols[2])
    return cv


def mushrooms4(seed):
    cv = S.Canvas(48, 36)
    rnd = random.Random(seed)
    cap_c = [hexc("4a0c0a"), hexc("7a1610"), hexc("a8261a"), hexc("cc4a30")]
    for k in range(4):
        x = 6 + k * 11 + rnd.uniform(-2, 2); h = rnd.uniform(8, 18); r = rnd.uniform(5, 8)
        for i in range(int(h)):
            cv.p(x, 35 - i, S.MAT["bone"][1]); cv.p(x + 1, 35 - i, S.MAT["bone"][2]); cv.p(x - 1, 35 - i, S.MAT["bone"][0])
        top = 35 - h
        for yy in range(int(r * 0.8)):
            hw = r * math.sqrt(max(0, 1 - (yy / (r * 0.8)) ** 2))
            for xx in range(int(-hw), int(hw) + 1):
                l = -xx / max(hw, 1) * 0.6 - yy / r * 0.4 + 0.3
                cv.p(x + xx, top - (r * 0.8 - yy) + r * 0.3, cap_c[int(np.clip((l + 0.5) * 2.5, 0, 3))])
        for d in range(3):
            cv.p(x + rnd.randint(int(-r * 0.6), int(r * 0.6)), top - r * 0.3 + rnd.randint(-1, 1), (235, 225, 205, 255))
    return cv


def flame(cv, cx, base, height, width, frame, seed=0):
    rnd = random.Random(frame * 13 + seed)
    fl = [hexc("6a1404"), hexc("a82a08"), hexc("d8500e"), hexc("f08a24"), hexc("ffc050"), hexc("fff0b8")]
    for y in range(int(height)):
        t = y / height
        half = (1 - t) ** 0.8 * width * (0.85 + 0.25 * math.sin(frame * 1.9 + y * 0.25)) + 0.6
        sway = math.sin(frame * 1.4 + y * 0.12) * t * width * 0.45
        for x in range(int(-half) - 1, int(half) + 2):
            inner = 1 - abs(x) / max(half, 1)
            if inner < 0:
                continue
            k = int(np.clip(inner * 3.4 + (1 - t) * 2.0 - 0.6 + rnd.uniform(-0.4, 0.4), 0, 5))
            cv.p(cx + x + sway, base - y, fl[k])
    for i in range(int(width)):
        cv.p(cx + rnd.uniform(-width, width), base - height - rnd.uniform(0, height * 0.4), fl[4])


def campfire4(frame):
    cv = S.Canvas(112, 120)
    rnd = random.Random(1)
    st = [hexc("1e1e22"), hexc("34343a"), hexc("4e4e56"), hexc("6e6e76")]
    for i in range(12):
        a = i / 12 * math.tau
        cx, cy = 56 + math.cos(a) * 40, 98 + math.sin(a) * 15
        for yy in range(-6, 7):
            for xx in range(-8, 9):
                if (xx / 8) ** 2 + (yy / 6) ** 2 <= 1:
                    l = -xx / 8 * 0.5 - yy / 6 * 0.6 + rnd.uniform(-0.15, 0.15)
                    cv.p(cx + xx, cy + yy, st[int(np.clip((l + 0.6) * 2.4, 0, 3))])
    for (x0, y0, x1, y1) in [(28, 102, 84, 90), (28, 90, 84, 102), (40, 106, 72, 84)]:
        n = int(max(abs(x1 - x0), abs(y1 - y0)))
        for i in range(n):
            x = x0 + (x1 - x0) * i / n; y = y0 + (y1 - y0) * i / n
            for w in range(-3, 4):
                cv.p(x, y + w, S.MAT["wood"][2 if w < 0 else (1 if w < 2 else 0)])
            if i % 7 == 0:
                cv.p(x, y + 3, hexc("ff7a20"))
    flame(cv, 56, 96, 80, 22, frame)
    return cv


def torch4(frame):
    cv = S.Canvas(40, 120)
    for y in range(40, 120):
        for x in range(17, 23):
            cv.p(x, y, S.MAT["wood"][2 if x < 19 else (1 if x < 21 else 0)])
    for y in range(34, 42):
        for x in range(13, 27):
            cv.p(x, y, S.MAT["iron_dark"][1 if x < 20 else 0])
    flame(cv, 20, 36, 32, 8, frame, 4)
    return cv


def brazier4(frame):
    cv = S.Canvas(56, 88)
    ir = S.MAT["iron_dark"]
    for (x0, x1) in [(16, 8), (40, 48), (28, 28)]:
        for y in range(56, 88):
            t = (y - 56) / 32
            cv.p(x0 + (x1 - x0) * t, y, ir[1]); cv.p(x0 + (x1 - x0) * t + 1, y, ir[0])
    for y in range(40, 56):
        hw = 18 - (y - 40) * 0.5
        for x in range(int(28 - hw), int(28 + hw)):
            cv.p(x, y, ir[2] if x < 22 else ir[1] if x < 34 else ir[0])
    flame(cv, 28, 42, 36, 13, frame, 9)
    return cv


def main():
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(manifest_path))
    props = {}
    for i in range(4):
        props[f"pine_{i}"] = pine4(i + 1, (52 + (i % 2) * 8) * K, (88 + (i % 3) * 10) * K).img
    for i in range(3):
        old_k = P2.K
        P2.K = K
        props[f"rock_{i}"] = P2.rock_hi(i, (26 - i * 4), (18 - i * 3)).img
        P2.K = old_k
    for i in range(4):
        props[f"grass_{i}"] = grass4(i).img
    props["reeds"] = reeds4().img
    props["fern"] = fern4().img
    for i in range(2):
        props[f"mushrooms_{i}"] = mushrooms4(10 + i).img
    for f in range(4):
        props[f"campfire_{f}"] = campfire4(f).img
    for f in range(3):
        props[f"torch_{f}"] = torch4(f).img
        props[f"brazier_{f}"] = brazier4(f).img
    # outline the natives (not flames)
    for name in list(props):
        if not name.startswith(("campfire", "torch", "brazier")):
            cv = S.Canvas(props[name].width, props[name].height)
            cv.img = props[name]; cv.px = cv.img.load()
            cv.outline()
            props[name] = P2.detail(cv.img, 0.04, hash(name) % 31)
    # lift the rest from the 2x set
    for name, meta in list(manifest["props"].items()):
        if name in props:
            continue
        src = Image.open(os.path.join(OUT, f"prop_{name}.png"))
        if meta.get("scale", 0.5) == 0.25:
            props[name] = src
            continue
        up = src.resize((src.width * 2, src.height * 2), Image.NEAREST)
        if not name.startswith(("moth", "nana", "loot")):
            up = P2.detail(up, 0.05, hash(name) % 53)
        props[name] = up
    manifest["props"] = {}
    for name, img in props.items():
        img.save(os.path.join(OUT, f"prop_{name}.png"))
        if not name.startswith(("campfire", "torch", "brazier", "moth", "nana", "grass", "fern", "reeds", "mushrooms")):
            normal_from(img, 2.6 if name.startswith("pine") else 2.0, 4 if name.startswith(("pine", "rock", "ruin")) else 2).save(os.path.join(OUT, f"prop_{name}_n.png"))
            has_n = True
        else:
            has_n = False
        manifest["props"][name] = {"w": img.width, "h": img.height, "scale": 0.25, "normal": has_n}
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    print("props", len(props))


if __name__ == "__main__":
    main()


def nana_puppet():
    """Nana Ithriel as a ghostly little old woman, rendered with the puppet renderer."""
    import render3d as R
    R.mat("ghost", "#9ab4e8", spread=0.5)
    R.mat("ghost_hair", "#d8e2f8", "strand", 0.2, spread=0.3)
    spec = R.spec(leg=20, torso=14, head=11, sh_w=5.0, chest_r=5.4, waist_r=5.0, thigh_r=2.2, arm_r=1.8, arm=16,
                  hunch=14, skin="ghost", top="ghost", arms="ghost", legs="ghost", boots="ghost", robe="ghost", robe_r=8.0,
                  hair="ghost_hair", pauldrons="ghost", pauldrons_r=3.6)
    pup = R.Puppet(spec)
    W, H = 120, 150
    pose = {"shL": 30, "shR": 30, "elbL": 70, "elbR": 70, "rollL": -10, "rollR": -10}
    J = pup.joints(pose)
    prims = pup.dress(J, pose)
    head = J["head"]
    prims.append((head + R.V(0, 6.5, -2), head + R.V(0, 6.5, -2), 3.2, 3.2, "ghost_hair", "hair"))
    img, _ = R.render(prims, 10.0, W, H, H - 10)
    a = np.array(img).astype(np.float32)
    m = a[:, :, 3] > 0
    a[:, :, 3][m] = 170
    # fade towards the feet like a ghost
    for y in range(H):
        t = max(0.0, (y - H * 0.6) / (H * 0.4))
        a[y, :, 3] *= (1 - t)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


if __name__ == "__main__" and True:
    nana_puppet().save(os.path.join(OUT, "prop_nana.png"))
    mp = os.path.join(OUT, "manifest.json")
    man = json.load(open(mp))
    im = Image.open(os.path.join(OUT, "prop_nana.png"))
    man["props"]["nana"] = {"w": im.width, "h": im.height, "scale": 0.25, "normal": False}
    json.dump(man, open(mp, "w"), indent=1)
    print("nana", im.size)
