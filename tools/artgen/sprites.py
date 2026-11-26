"""Hollowmoth pixel-art generator.

Draws every character and prop pixel by pixel (PIL), Drova-style:
top-down 3/4 view, muted earthy palette, 3-tone shading lit from the upper
left, and a dark selective outline. Output: PNG sheets + a JSON manifest
that Godot reads to build SpriteFrames.

Character sheet layout (one row per direction: down, side, up):
  cols 0-1 idle, 2-5 walk, 6-8 attack (windup, strike, follow), 9 hurt, 10-11 cast
Row 3: col 0 dead.
"""
import json, math, os, random
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

OUTLINE = (18, 12, 16, 255)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def ramp(dark, mid, light):
    return [hexc(dark), hexc(mid), hexc(light)]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()

    def p(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            if len(c) == 4 and c[3] < 255:
                old = self.px[x, y]
                a = c[3] / 255.0
                if old[3] == 0:
                    self.px[x, y] = c
                else:
                    self.px[x, y] = tuple(int(old[i] * (1 - a) + c[i] * a) for i in range(3)) + (255,)
            else:
                self.px[x, y] = c

    def rect(self, x, y, w, h, c):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.p(xx, yy, c)

    def shaded(self, x, y, w, h, r, light_cols=1, dark_cols=1, dark_bottom=1):
        """Rectangle with a lit left edge and shaded right/bottom (light from upper left)."""
        self.rect(x, y, w, h, r[1])
        if w > 2:
            self.rect(x, y, light_cols, h, r[2])
            self.rect(x + w - dark_cols, y, dark_cols, h, r[0])
        if dark_bottom and h > 2:
            self.rect(x, y + h - dark_bottom, w, dark_bottom, r[0])

    def texture(self, x, y, w, h, r, kind, seed=0):
        """Material detail inside an already-shaded rect."""
        rnd = random.Random(seed + x * 31 + y * 17)
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                if not (0 <= xx < self.w and 0 <= yy < self.h) or self.px[xx, yy][3] == 0:
                    continue
                if kind == "mail" and (xx + yy) % 2 == 0:
                    self.p(xx, yy, r[0])
                elif kind == "fur" and rnd.random() < 0.28:
                    self.p(xx, yy, r[2] if rnd.random() < 0.5 else r[0])
                elif kind == "cloth" and (xx - int(x)) == int(w * 0.62) and yy > y + 1:
                    self.p(xx, yy, r[0])
                elif kind == "robe" and (xx - int(x)) in (int(w * 0.3), int(w * 0.7)) and yy > y + 1:
                    self.p(xx, yy, r[0])
                elif kind == "rag" and rnd.random() < 0.18:
                    self.p(xx, yy, r[0])
                elif kind == "plate" and (yy - int(y)) % 4 == 0:
                    self.p(xx, yy, r[2] if xx < x + w / 2 else r[0])

    def clear(self, x, y):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = (0, 0, 0, 0)

    def round_corners(self, x, y, w, h, top=True, bottom=False):
        if top:
            self.clear(x, y); self.clear(x + w - 1, y)
        if bottom:
            self.clear(x, y + h - 1); self.clear(x + w - 1, y + h - 1)

    def line(self, x0, y0, x1, y1, c):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n):
            t = i / max(1, n - 1)
            self.p(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for yy in range(int(cy - ry), int(cy + ry) + 1):
            for xx in range(int(cx - rx), int(cx + rx) + 1):
                if ((xx - cx) / max(rx, 0.5)) ** 2 + ((yy - cy) / max(ry, 0.5)) ** 2 <= 1.0:
                    self.p(xx, yy, c)

    def outline(self, color=OUTLINE):
        src = self.img.copy().load()
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[nx, ny][3] > 200:
                        self.px[x, y] = color
                        break


# ---------------------------------------------------------------- palettes
SKIN = {
    "human": ramp("7a4a3a", "b07a5c", "d6a17e"),
    "elf": ramp("8a6a58", "c4a488", "e6cdb0"),
    "dwarf": ramp("7a4634", "aa6e52", "cf9474"),
    "pale": ramp("8c8a92", "c8c4c8", "eceaf0"),
    "ghoul": ramp("3e4a3a", "66745a", "8e9a76"),
    "brute": ramp("5a3e30", "84604a", "a88066"),
    "shadow": ramp("140e18", "241a2a", "3a2c40"),
    "iron": ramp("2c2c32", "4c4c56", "7a7a86"),
}

MAT = {
    "fur": ramp("3c2a1c", "6a4c32", "947050"),
    "leather": ramp("2e2018", "4e3626", "6e503a"),
    "leather_red": ramp("3a1a14", "5e2a1e", "84402c"),
    "cloth_green": ramp("1c2a20", "2f4434", "4a634c"),
    "cloth_moss": ramp("26301c", "3e4c2a", "5a6a3c"),
    "cloth_black": ramp("0e0e14", "1c1c26", "30303e"),
    "silver": ramp("5e6068", "9a9ca6", "d8dae2"),
    "mail": ramp("34363c", "5a5e66", "868a94"),
    "steel": ramp("3a3e46", "6a707c", "aab0bc"),
    "iron_dark": ramp("1e1e24", "34343c", "54545e"),
    "wood": ramp("2e1e12", "4a3220", "6a4a30"),
    "rag": ramp("2a241c", "443a2c", "625440"),
    "robe_purple": ramp("1a1022", "2e1c3a", "48305a"),
    "bone": ramp("8a8270", "bab29a", "e2dcc4"),
    "gold": ramp("6a4a14", "a87a24", "e0b44a"),
}

HAIR = {
    "brown": ramp("2a160c", "4a2a16", "6e4224"),
    "purple": ramp("2c1a38", "4c2e62", "7a52a0"),
    "orange": ramp("6a2a0c", "a64a14", "d8782c"),
    "white": ramp("8a8a98", "c8c8d4", "f0f0f8"),
    "black": ramp("0c0a0c", "1a1618", "2e2a2c"),
}


# ---------------------------------------------------------------- humanoid
TEX = {'fur': 'fur', 'mail': 'mail', 'rag': 'rag', 'cloth_green': 'cloth', 'cloth_black': 'robe', 'robe_purple': 'robe', 'iron_dark': 'plate', 'leather': 'cloth', 'cloth_moss': 'cloth'}


def draw_humanoid(cv, spec, view, pose):
    """spec: body proportions and materials; view: down|side|up; pose: dict."""
    S = spec
    cx = cv.w // 2 + pose.get("lean", 0)
    gy = cv.h - 3                       # ground line (feet)
    bob = pose.get("bob", 0)
    leg_h = S["leg_h"]
    tor_h = S["torso_h"]
    hw = S["torso_w"] // 2
    head = S["head"]
    hunch = S.get("hunch", 0)
    legs_top = gy - leg_h
    tor_top = legs_top - tor_h + bob
    head_top = tor_top - head + 1 + hunch
    skin = SKIN[S["skin"]]
    top = MAT[S["top"]]
    bottom = MAT[S["bottom"]]
    boots = MAT[S.get("boots", "leather")]
    hair = HAIR.get(S.get("hair", "brown"), HAIR["brown"])
    side = view == "side"
    lw = S.get("leg_w", 3)

    def legs():
        step = pose.get("step", 0)
        if side:
            # back leg darker, front leg normal; step moves them apart
            bx, fx = cx - 1 - step, cx - 1 + step
            cv.shaded(bx, legs_top, lw, leg_h, [bottom[0], bottom[0], bottom[1]], 0, 0, 0)
            cv.rect(bx, gy - 2, lw + 1, 2, boots[0])
            cv.shaded(fx, legs_top, lw, leg_h, bottom)
            cv.rect(fx, gy - 2, lw + 1, 2, boots[1])
        else:
            l_lift = max(0, step)
            r_lift = max(0, -step)
            lx, rx = cx - lw - 1, cx + 1
            if S.get("robe"):
                # robe hem instead of legs
                cv.shaded(cx - hw, legs_top, hw * 2, leg_h - 1, top, 1, 1, 0)
                cv.rect(cx - hw, gy - 2, hw * 2, 1, top[0])
                cv.rect(lx, gy - 1 - l_lift, lw, 1 + l_lift, boots[0])
                cv.rect(rx, gy - 1 - r_lift, lw, 1 + r_lift, boots[0])
                return
            cv.shaded(lx, legs_top, lw, leg_h - l_lift, bottom, 1, 0, 0)
            cv.texture(lx, legs_top, lw * 2 + 2, leg_h - 2, bottom, TEX.get(S["bottom"], "") if S["bottom"] in ("iron_dark", "mail", "fur") else "", 3)
            cv.rect(lx, gy - 2 - l_lift, lw, 2, boots[1])
            cv.shaded(rx, legs_top, lw, leg_h - r_lift, bottom, 0, 1, 0)
            cv.rect(rx, gy - 2 - r_lift, lw, 2, boots[0])

    def torso():
        w = hw * 2 if not side else max(4, hw * 2 - 3)
        x = cx - w // 2
        cv.shaded(x, tor_top, w, tor_h, top, 1, 1 if w < 8 else 2, 1)
        cv.texture(x, tor_top, w, tor_h, top, TEX.get(S["top"], ""), len(S["top"]))
        # taper toward the waist so it reads as a body, not a box
        if w >= 8 and not S.get("robe"):
            for k in range(tor_h // 2, tor_h - 1):
                cv.clear(x, tor_top + k); cv.clear(x + w - 1, tor_top + k)
        cv.round_corners(x, tor_top, w, tor_h)
        if S.get("bare_chest") and view != "up":
            cv.shaded(x + 1, tor_top + 1, w - 2, tor_h - 3, skin, 1, 1, 0)
            # scars
            cv.p(x + 2, tor_top + 3, skin[0])
            cv.p(x + 3, tor_top + 4, skin[0])
            cv.p(x + w - 3, tor_top + 2, skin[0])
        if S.get("trim"):
            t = MAT[S["trim"]]
            if view == "down":
                cv.rect(cx, tor_top + 1, 1, tor_h - 1, t[1])
                cv.rect(x, tor_top, w, 1, t[2])
            elif view == "up":
                cv.rect(x, tor_top, w, 1, t[1])
        if S.get("belt"):
            b = MAT[S["belt"]]
            cv.rect(x, tor_top + tor_h - 2, w, 1, b[0])
            if view == "down":
                cv.p(cx, tor_top + tor_h - 2, MAT["gold"][2])
        if S.get("pouch") and view != "up":
            cv.rect(x + w - 2 if not side else x - 1, tor_top + tor_h - 3, 2, 2, MAT["leather"][2])
        if S.get("shoulders"):
            sm = MAT[S["shoulders"]]
            if side:
                cv.shaded(x - 1, tor_top - 1, w + 2, 3, sm, 1, 1, 1)
            else:
                cv.shaded(x - 2, tor_top - 1, 4, 3, sm, 1, 0, 1)
                cv.shaded(x + w - 2, tor_top - 1, 4, 3, sm, 0, 1, 1)
        if S.get("cape") and view == "up":
            c = MAT[S["cape"]]
            cv.shaded(x - 1, tor_top, w + 2, tor_h + leg_h - 3, c, 1, 1, 1)

    def head_draw():
        hwid = S.get("head_w", head)
        hx = cx - hwid // 2 + (1 if side else 0)
        cv.shaded(hx, head_top, hwid, head, skin, 1, 1, 1)
        cv.round_corners(hx, head_top, hwid, head, True, True)
        # hair
        if S.get("hood"):
            h = MAT[S["hood"]]
            cv.shaded(hx - 1, head_top - 1, hwid + 2, head - 1 if view != "up" else head + 1, h, 1, 1, 0)
            cv.round_corners(hx - 1, head_top - 1, hwid + 2, head)
            tip_x = cx + (2 if side else 0) - (1 if view == "up" else 0)
            cv.rect(tip_x - 1, head_top - 3, 2, 2, h[1]); cv.p(tip_x - (2 if side else 0), head_top - 4, h[1])
            if view == "down":
                cv.rect(hx + 1, head_top + 2, hwid - 2, head - 3, SKIN["shadow"][1])
                cv.p(hx + 2, head_top + 3, S.get("eye", (200, 160, 255, 255)))
                cv.p(hx + hwid - 3, head_top + 3, S.get("eye", (200, 160, 255, 255)))
            elif side:
                cv.rect(hx + hwid - 2, head_top + 2, 2, head - 3, SKIN["shadow"][1])
                cv.p(hx + hwid - 1, head_top + 3, S.get("eye", (200, 160, 255, 255)))
            return
        if S.get("helm"):
            hm = MAT[S["helm"]]
            cv.shaded(hx - 1, head_top - 1, hwid + 2, 4, hm, 1, 1, 0)
            cv.round_corners(hx - 1, head_top - 1, hwid + 2, 4)
            if view == "down":
                cv.rect(cx, head_top + 2, 1, 2, hm[2])   # nasal guard
            if S.get("spike"):
                cv.rect(cx, head_top - 4, 1, 3, hm[2])
            if view == "up":
                cv.shaded(hx - 1, head_top - 1, hwid + 2, head, hm, 1, 1, 1)
        elif view == "up":
            cv.shaded(hx, head_top, hwid, head - 1, hair, 1, 1, 0)
        else:
            cv.rect(hx, head_top, hwid, 2, hair[1])
            cv.rect(hx, head_top, 1, 2, hair[2])
            if side:
                cv.rect(hx, head_top, 2, head - 2, hair[1])   # hair at the back of the head
            else:
                cv.rect(hx - 1 if S.get("long_hair") else hx, head_top + 1, 1, head - 1 if S.get("long_hair") else 2, hair[0])
                if S.get("long_hair"):
                    cv.rect(hx + hwid, head_top + 1, 1, head - 1, hair[0])
        if S.get("ears") and view != "up":
            if side:
                cv.p(hx + 1, head_top + 2, skin[2]); cv.p(hx, head_top + 1, skin[2])
            else:
                cv.p(hx - 1, head_top + 2, skin[1]); cv.p(hx - 2, head_top + 1, skin[2])
                cv.p(hx + hwid, head_top + 2, skin[0]); cv.p(hx + hwid + 1, head_top + 1, skin[1])
        eye = S.get("eye", (24, 16, 16, 255))
        if view == "down":
            ey = head_top + head // 2
            cv.p(cx - 2, ey, eye)
            cv.p(cx + 1, ey, eye)
            if S.get("beard"):
                b = HAIR[S["beard"]]
                cv.shaded(hx, ey + 1, hwid, head - (ey - head_top), b, 1, 1, 0)
                cv.shaded(hx + 1, ey + head - (ey - head_top), hwid - 2, 3, b, 1, 1, 1)
        elif side:
            ey = head_top + head // 2
            cv.p(hx + hwid - 2, ey, eye)
            cv.p(hx + hwid, ey + 1, skin[1])      # nose
            if S.get("beard"):
                b = HAIR[S["beard"]]
                cv.shaded(hx + 2, ey + 1, hwid - 1, head - (ey - head_top) + 2, b, 1, 1, 0)
        if S.get("braid") and view != "down":
            cv.rect(hx + (0 if view == "up" else 1), head_top + head, 1, 4, hair[1])

    def arm(back, front_side):
        """Draws one arm. front_side True = weapon arm."""
        ax_off = hw + (0 if side else 1)
        if side:
            ax = cx - 1 + (0 if front_side else -2)
        else:
            ax = cx + ax_off if front_side else cx - ax_off - 2
        ay = tor_top + 1
        arm_len = tor_h - 1
        swing = pose.get("arm_swing", 0) * (1 if front_side else -1)
        col = MAT[S.get("sleeve", S["top"])] if not S.get("bare_arms") else skin
        if S.get("bare_arms"):
            col = skin
        c = col if not back else [col[0], col[0], col[1]]
        cv.shaded(ax, ay + (swing if not side else 0), 2, arm_len - 2, c, 1, 0, 0)
        hand = (ax + (1 if not side else swing), ay + arm_len - 2 + (swing if not side else 0))
        cv.rect(hand[0] - (1 if not side else 0), hand[1], 2, 2, skin[1])
        return hand

    def weapon(hand):
        w = S.get("weapon")
        if not w:
            return
        ang = pose.get("weapon_angle", None)
        if ang is None:
            ang = {"down": 100, "side": 70, "up": -80}[view]
        a = math.radians(ang)
        if view == "side":
            dx, dy = math.cos(a), math.sin(a)
        else:
            dx, dy = math.cos(a) * 0.8, math.sin(a)
        hx, hy = hand
        if w == "axe":
            L = 17
            ex, ey = hx + dx * L, hy + dy * L
            cv.line(hx - dx * 3, hy - dy * 3, ex, ey, MAT["wood"][1])
            # head
            nx, ny = -dy, dx
            for k in range(5):
                for j in range(-1, 6):
                    cv.p(ex - dx * k + nx * j, ey - dy * k + ny * j, MAT["steel"][1 if j < 3 else 0])
            cv.line(ex + nx * 4, ey + ny * 4, ex - dx * 3 + nx * 4, ey - dy * 3 + ny * 4, MAT["steel"][2])
        elif w == "rapier":
            L = 16
            ex, ey = hx + dx * L, hy + dy * L
            cv.line(hx, hy, ex, ey, MAT["silver"][2])
            cv.line(hx - dy * 1.5, hy + dx * 1.5, hx + dy * 1.5, hy - dx * 1.5, MAT["gold"][1])
        elif w == "starknife":
            sx, sy = hx + dx * 3, hy + dy * 3
            for k in range(-2, 3):
                cv.p(sx + k, sy, MAT["silver"][1]); cv.p(sx, sy + k, MAT["silver"][1])
            cv.p(sx, sy, MAT["silver"][2])
        elif w == "bow":
            # bow held vertically in front
            bx = hx + (2 if view != "up" else 0)
            pull = pose.get("pull", 0)
            for k in range(-6, 7):
                off = int(round(math.cos(k / 6 * math.pi / 2) * 2))
                cv.p(bx + off, hy + k - 2, MAT["wood"][2 if k < 0 else 1])
            cv.line(bx, hy - 8, bx - pull, hy - 2, (200, 200, 190, 255))
            cv.line(bx - pull, hy - 2, bx, hy + 4, (200, 200, 190, 255))
            if pull:
                cv.line(bx - pull, hy - 2, bx + 6, hy - 2, MAT["wood"][2])
        elif w == "claws":
            for k in range(3):
                cv.line(hx + k - 1, hy + 1, hx + k - 1 + dx * 3, hy + 1 + dy * 3 + 1, MAT["bone"][2 if k == 0 else 1])
        elif w == "staff":
            cv.line(hx, hy + 6, hx, hy - 12, MAT["wood"][1])
            cv.ellipse(hx, hy - 13, 1.5, 1.5, (150, 90, 230, 255))
            cv.p(hx - 1, hy - 14, (220, 190, 255, 255))
        elif w == "club":
            L = 16
            ex, ey = hx + dx * L, hy + dy * L
            cv.line(hx, hy, ex, ey, MAT["wood"][1])
            cv.ellipse(ex, ey, 3.5, 3.5, MAT["wood"][1])
            cv.ellipse(ex - 1, ey - 1, 1.5, 1.5, MAT["wood"][2])
            for q in range(4):
                cv.p(ex + math.cos(q * 1.6) * 4, ey + math.sin(q * 1.6) * 4, MAT["bone"][2])
            cv.p(ex - 1, ey - 1, MAT["bone"][2])
        elif w == "hammer":
            L = 22
            ex, ey = hx + dx * L, hy + dy * L
            cv.line(hx - dx * 4, hy - dy * 4, ex, ey, MAT["wood"][0])
            nx, ny = -dy, dx
            for k in range(-4, 4):
                for j in range(-5, 6):
                    cv.p(ex - dx * k + nx * j, ey - dy * k + ny * j, MAT["iron_dark"][1] if abs(j) < 5 else MAT["iron_dark"][0])
            cv.line(ex + dx * 4 - nx * 5, ey + dy * 4 - ny * 5, ex + dx * 4 + nx * 5, ey + dy * 4 + ny * 5, MAT["steel"][2])

    # draw order depends on view
    if view == "up":
        weapon_hand = arm(False, True)
        if S.get("weapon") not in ("bow",):
            weapon(weapon_hand)
        legs(); torso(); arm(False, False); head_draw()
        if S.get("weapon") == "bow":
            weapon(weapon_hand)
    elif view == "side":
        arm(True, False)
        legs(); torso(); head_draw()
        hand = arm(False, True)
        weapon(hand)
    else:
        legs(); torso()
        left = arm(False, False)
        hand = arm(False, True)
        head_draw()
        weapon(hand)
    if S.get("raise_arms"):
        for sx in (-1, 1):
            cv.rect(cx + sx * (hw + 2) - (1 if sx < 0 else 0), tor_top - 5, 2, 6, skin[1])


def draw_dead(cv, spec):
    S = spec
    skin = SKIN[S["skin"]]
    top = MAT[S["top"]]
    bottom = MAT[S["bottom"]]
    gy = cv.h - 6
    cx = cv.w // 2
    # blood pool
    cv.ellipse(cx, gy + 1, S["torso_h"] + 3, 3, (90, 10, 10, 255))
    cv.ellipse(cx + 2, gy + 1, S["torso_h"], 2, (120, 16, 14, 255))
    L = S["torso_h"] + S["leg_h"]
    x0 = cx - L // 2
    cv.shaded(x0 + S["torso_h"], gy - 2, S["leg_h"], 3, bottom)
    cv.shaded(x0, gy - S["torso_w"] // 2 + 1, S["torso_h"], S["torso_w"] - 2, top)
    hd = S["head"]
    cv.shaded(x0 - hd + 1, gy - hd // 2 - 1, hd, hd - 1, skin)
    if S.get("hood"):
        cv.shaded(x0 - hd, gy - hd // 2 - 2, hd + 1, hd - 1, MAT[S["hood"]])
    w = S.get("weapon")
    if w in ("axe", "rapier", "club", "hammer", "staff"):
        cv.line(x0 + 2, gy + 3, x0 + L, gy + 4, MAT["steel"][1] if w != "staff" else MAT["wood"][1])


ANIMS = [("idle", 2), ("walk", 4), ("attack", 3), ("hurt", 1), ("cast", 2)]


def pose_for(anim, i, view, spec):
    p = {}
    if anim == "idle":
        p["bob"] = 0 if i == 0 else 1
    elif anim == "walk":
        p["step"] = [1, 0, -1, 0][i] * (2 if view == "side" else 1)
        p["bob"] = [0, -1, 0, -1][i]
        p["arm_swing"] = [1, 0, -1, 0][i]
    elif anim == "attack":
        w = spec.get("weapon")
        if w == "bow":
            p["pull"] = [2, 3, 0][i]
            p["weapon_angle"] = 0
        else:
            ang = {"down": [-130, 70, 110], "side": [-120, 10, 60], "up": [-60, -110, -150]}[view][i]
            p["weapon_angle"] = ang
            p["lean"] = [-1, 1, 0][i] if view == "side" else 0
            p["bob"] = [-1, 1, 0][i]
    elif anim == "hurt":
        p["lean"] = -2 if view == "side" else 0
        p["bob"] = 1
        p["weapon_angle"] = {"down": 140, "side": 150, "up": -40}[view]
    elif anim == "cast":
        p["bob"] = -1 + i
        p["weapon_angle"] = {"down": -90, "side": -80, "up": -90}[view]
    return p


def build_character(name, spec, fw, fh):
    cols = sum(n for _, n in ANIMS)
    sheet = Image.new("RGBA", (fw * cols, fh * 4), (0, 0, 0, 0))
    meta = {"frame_w": fw, "frame_h": fh, "anims": {}}
    for row, view in enumerate(["down", "side", "up"]):
        col = 0
        for anim, n in ANIMS:
            meta["anims"][f"{anim}_{view}"] = {"row": row, "col": col, "count": n}
            for i in range(n):
                cv = Canvas(fw, fh)
                s = dict(spec)
                if anim == "cast":
                    s["raise_arms"] = True
                draw_humanoid(cv, s, view, pose_for(anim, i, view, spec))
                cv.outline()
                sheet.paste(cv.img, ((col + i) * fw, row * fh))
            col += n
    cv = Canvas(fw, fh)
    draw_dead(cv, spec)
    cv.outline()
    sheet.paste(cv.img, (0, 3 * fh))
    meta["anims"]["dead"] = {"row": 3, "col": 0, "count": 1}
    sheet.save(os.path.join(OUT, f"{name}.png"))
    return meta


CHARACTERS = {
    "average": ({"skin": "human", "top": "fur", "bottom": "leather", "boots": "fur", "hair": "brown", "bare_chest": True,
                 "bare_arms": True, "shoulders": "fur", "belt": "leather_red", "weapon": "axe", "braid": True,
                 "leg_h": 9, "torso_h": 11, "torso_w": 12, "head": 7, "leg_w": 4}, 40, 44),
    "puck": ({"skin": "elf", "top": "cloth_green", "bottom": "leather", "hair": "purple", "ears": True, "cape": "cloth_moss",
              "belt": "leather", "pouch": True, "weapon": "rapier", "shoulders": "cloth_moss",
              "leg_h": 9, "torso_h": 9, "torso_w": 8, "head": 7, "leg_w": 3}, 36, 40),
    "brokk": ({"skin": "dwarf", "top": "mail", "bottom": "leather", "hair": "orange", "beard": "orange", "helm": "steel",
               "belt": "leather_red", "weapon": "bow", "shoulders": "leather", "sleeve": "leather",
               "leg_h": 6, "torso_h": 9, "torso_w": 11, "head": 7, "head_w": 8, "leg_w": 4}, 36, 40),
    "sael": ({"skin": "pale", "top": "cloth_black", "bottom": "cloth_black", "hair": "white", "long_hair": True, "ears": True,
              "trim": "silver", "robe": True, "weapon": "starknife", "belt": "silver",
              "leg_h": 9, "torso_h": 9, "torso_w": 8, "head": 7, "leg_w": 3}, 36, 40),
    "ghoul": ({"skin": "ghoul", "top": "rag", "bottom": "rag", "hair": "black", "bare_chest": True, "bare_arms": True,
               "weapon": "claws", "hunch": 2, "eye": (200, 220, 120, 255),
               "leg_h": 8, "torso_h": 9, "torso_w": 9, "head": 6, "leg_w": 3}, 32, 38),
    "cultist": ({"skin": "shadow", "top": "robe_purple", "bottom": "robe_purple", "hood": "robe_purple", "robe": True,
                 "trim": "bone", "weapon": "staff", "eye": (190, 140, 255, 255),
                 "leg_h": 9, "torso_h": 10, "torso_w": 9, "head": 7, "leg_w": 3}, 32, 42),
    "brute": ({"skin": "brute", "top": "rag", "bottom": "leather", "hair": "black", "bare_chest": True, "bare_arms": True,
               "belt": "leather", "weapon": "club", "hunch": 1,
               "leg_h": 11, "torso_h": 14, "torso_w": 18, "head": 8, "leg_w": 6}, 48, 52),
    "iron_brother": ({"skin": "iron", "top": "iron_dark", "bottom": "iron_dark", "boots": "iron_dark", "helm": "steel",
                      "spike": True, "shoulders": "steel", "belt": "leather_red", "trim": "steel", "weapon": "hammer",
                      "eye": (220, 60, 40, 255), "sleeve": "iron_dark",
                      "leg_h": 15, "torso_h": 18, "torso_w": 22, "head": 10, "leg_w": 7}, 72, 76),
}


# ---------------------------------------------------------------- props
def save(cv, name, outline=True):
    if outline:
        cv.outline()
    cv.img.save(os.path.join(OUT, name + ".png"))


def pine(seed, w=52, h=88):
    rnd = random.Random(seed)
    cv = Canvas(w, h)
    cx = w // 2
    trunk = MAT["wood"]
    cv.shaded(cx - 3, h - 18, 6, 16, trunk, 1, 2, 0)
    cv.rect(cx - 3, h - 18, 1, 16, (150, 80, 40, 255))   # firelit rim
    needles = [hexc("0d1c1c"), hexc("16302c"), hexc("214238"), hexc("2f5a48"), hexc("4a7a5a")]
    tiers = 6
    for t in range(tiers):
        top_y = int(4 + t * (h - 26) / tiers)
        tier_h = int((h - 18) / tiers * 1.7)
        for yy in range(tier_h):
            y = top_y + yy
            if y >= h - 12:
                break
            half = (yy / tier_h) * (6 + t * 3.6) + 1
            jag = rnd.randint(-1, 1)
            for xx in range(int(-half) - jag, int(half) + jag + 1):
                rel = xx / max(1, half)
                shade = 2 if rel < -0.3 else (1 if rel < 0.35 else 0)
                if yy > tier_h - 3:
                    shade = max(0, shade - 1)
                c = needles[shade + 1] if rnd.random() > 0.08 else needles[shade]
                cv.p(cx + xx, y, c)
            # needle highlights on the lit side
            if rnd.random() < 0.6:
                hx = cx - int(half * rnd.uniform(0.3, 0.9))
                cv.p(hx, y, needles[4])
    return cv


def dead_tree(seed):
    rnd = random.Random(seed)
    cv = Canvas(44, 64)
    bark = ramp("1a1614", "2e2824", "4a403a")
    cv.shaded(19, 30, 6, 32, bark, 1, 2, 0)
    def branch(x, y, ang, length, width):
        for i in range(length):
            x += math.cos(ang); y += math.sin(ang)
            for k in range(width):
                cv.p(x + k * 0.6, y, bark[1] if k == 0 else bark[0])
            ang += rnd.uniform(-0.25, 0.25)
            if length > 6 and i == length // 2 and rnd.random() < 0.8:
                branch(x, y, ang + rnd.choice([-0.8, 0.8]), length // 2, max(1, width - 1))
    branch(22, 32, -1.57, 22, 3)
    branch(21, 40, -2.5, 14, 2)
    branch(23, 36, -0.6, 15, 2)
    return cv


def rock(seed, w=26, h=18, moss=True):
    rnd = random.Random(seed)
    cv = Canvas(w, h)
    st = ramp("2a2a2e", "46464c", "6c6c72")
    cv.ellipse(w / 2, h / 2 + 1, w / 2 - 1, h / 2 - 1, st[1])
    for y in range(h):
        for x in range(w):
            if cv.px[x, y][3]:
                if x < w * 0.4 and y < h * 0.55:
                    cv.p(x, y, st[2])
                elif x > w * 0.6 or y > h * 0.7:
                    cv.p(x, y, st[0])
    if moss:
        mo = [hexc("2a3a1e"), hexc("3e5228"), hexc("587034")]
        for i in range(30):
            x = rnd.randint(2, w - 3); y = rnd.randint(1, h // 2)
            if cv.px[x, y][3]:
                cv.p(x, y, mo[rnd.randint(0, 2)])
    return cv


def standing_stone():
    cv = Canvas(24, 40)
    st = ramp("26262a", "424248", "66666c")
    cv.shaded(3, 4, 18, 34, st, 3, 4, 2)
    for x in range(3, 21):
        cv.p(x, 3 + abs(x - 12) // 3, st[1])
    mo = [hexc("2a3a1e"), hexc("3e5228"), hexc("587034")]
    rnd = random.Random(2)
    for i in range(50):
        x = rnd.randint(3, 20); y = rnd.choice([rnd.randint(3, 9), rnd.randint(30, 37)])
        cv.p(x, y, mo[rnd.randint(0, 2)])
    # carved rune
    cv.rect(10, 16, 1, 8, st[0]); cv.rect(8, 18, 5, 1, st[0]); cv.rect(9, 22, 3, 1, st[0])
    return cv


def moth_shrine():
    cv = Canvas(40, 48)
    st = ramp("24242a", "3e3e46", "62626c")
    cv.shaded(6, 40, 28, 6, st, 2, 3, 1)          # plinth
    cv.shaded(11, 8, 18, 33, st, 3, 4, 0)         # stone
    for x in range(11, 29):
        cv.p(x, 7 + abs(x - 20) // 3, st[1])
    # glowing moth carving
    glow = hexc("d8e0ff"); gl2 = hexc("8890c0")
    for (x, y) in [(15, 18), (16, 17), (16, 18), (16, 19), (17, 18), (17, 19), (18, 20), (23, 18), (24, 17), (24, 18), (24, 19), (23, 19), (22, 20)]:
        cv.p(x, y, glow)
    cv.rect(19, 16, 3, 8, gl2); cv.rect(20, 15, 1, 10, glow)
    # candles
    for x in (8, 31):
        cv.rect(x, 36, 2, 4, MAT["bone"][2]); cv.p(x, 35, hexc("ffcc66")); cv.p(x + 1, 34, hexc("ffeeaa"))
    mo = [hexc("2a3a1e"), hexc("3e5228"), hexc("587034")]
    rnd = random.Random(5)
    for i in range(40):
        cv.p(rnd.randint(11, 28), rnd.randint(7, 12), mo[rnd.randint(0, 2)])
    return cv


def campfire(frame):
    rnd = random.Random(frame * 7 + 1)
    cv = Canvas(28, 30)
    st = ramp("2a2a2e", "4a4a50", "6c6c72")
    for i in range(10):
        a = i / 10 * math.tau
        x = 14 + math.cos(a) * 10; y = 24 + math.sin(a) * 4
        cv.shaded(x - 2, y - 1, 4, 3, st, 1, 1, 1)
    cv.line(7, 25, 21, 22, MAT["wood"][1]); cv.line(7, 22, 21, 25, MAT["wood"][2])
    fl = [hexc("8a1e08"), hexc("d24a10"), hexc("f08a24"), hexc("ffd060"), hexc("fff4c0")]
    for y in range(4, 24):
        t = (24 - y) / 20
        half = (1 - t) * 6 * (0.8 + 0.3 * math.sin(frame * 1.7 + y * 0.6)) + 0.5
        sway = math.sin(frame * 1.3 + y * 0.35) * t * 2
        for x in range(int(-half), int(half) + 1):
            inner = 1 - abs(x) / max(half, 1)
            k = min(4, int(inner * 3 + (1 - t) * 1.5))
            if rnd.random() < 0.08:
                k = max(0, k - 1)
            cv.p(14 + x + sway, y, fl[k])
    for i in range(3):
        cv.p(14 + rnd.randint(-5, 5), rnd.randint(0, 6), fl[3])
    return cv


def torch(frame):
    cv = Canvas(10, 30)
    cv.shaded(4, 10, 2, 20, MAT["wood"], 1, 0, 0)
    cv.rect(3, 9, 4, 2, MAT["iron_dark"][1])
    fl = [hexc("d24a10"), hexc("f08a24"), hexc("ffd060"), hexc("fff4c0")]
    for y in range(1, 9):
        t = (9 - y) / 8
        half = (1 - t) * 2.5 + 0.4
        sway = math.sin(frame * 2.1 + y) * t
        for x in range(int(-half), int(half) + 1):
            k = min(3, int((1 - abs(x) / max(half, 1)) * 2 + (1 - t) * 1.6))
            cv.p(5 + x + sway, y, fl[k])
    return cv


def gibbet():
    cv = Canvas(26, 44)
    w = MAT["wood"]
    cv.shaded(3, 4, 3, 40, w, 1, 1, 0)
    cv.shaded(3, 3, 18, 3, w, 1, 0, 1)
    cv.line(16, 6, 16, 12, MAT["iron_dark"][2])
    ir = MAT["iron_dark"]
    for x in range(12, 22, 3):
        cv.rect(x, 12, 1, 18, ir[2])
    cv.rect(12, 12, 10, 1, ir[2]); cv.rect(12, 29, 10, 1, ir[2]); cv.rect(11, 20, 12, 1, ir[1])
    sk = SKIN["ghoul"]
    cv.shaded(15, 15, 4, 4, MAT["bone"], 1, 1, 0)
    cv.shaded(14, 19, 6, 8, MAT["rag"], 1, 1, 0)
    cv.p(16, 17, OUTLINE); cv.p(18, 17, OUTLINE)
    cv.rect(16, 27, 1, 3, sk[1])
    return cv


def corpse(seed):
    rnd = random.Random(seed)
    cv = Canvas(26, 14)
    cv.ellipse(13, 9, 11, 3, (80, 10, 10, 255))
    cv.shaded(5, 5, 12, 5, MAT[rnd.choice(["rag", "leather", "cloth_moss"])], 1, 1, 1)
    cv.shaded(17, 6, 6, 3, MAT["leather"], 1, 1, 0)
    cv.shaded(1, 4, 5, 5, SKIN[rnd.choice(["human", "ghoul", "pale"])], 1, 1, 1)
    if rnd.random() < 0.5:
        cv.line(8, 11, 22, 12, MAT["steel"][1])
    return cv


def ruin_wall(seed, w=56, h=34):
    rnd = random.Random(seed)
    cv = Canvas(w, h)
    st = ramp("22222a", "3a3a44", "54545e")
    top_profile = [int(6 + 10 * abs(math.sin(x * 0.11 + seed)) + rnd.randint(0, 2)) for x in range(w)]
    for x in range(w):
        for y in range(top_profile[x], h):
            row = (y - 2) // 5
            off = (row % 2) * 5
            mortar = (y % 5 == 0) or ((x + off) % 10 == 0)
            c = st[0] if mortar else (st[2] if (x + off) % 10 in (1, 2) and y % 5 == 1 else st[1])
            if rnd.random() < 0.04:
                c = st[0]
            cv.p(x, y, c)
    mo = [hexc("2a3a1e"), hexc("3e5228"), hexc("587034")]
    for x in range(w):
        for k in range(rnd.randint(0, 3)):
            cv.p(x, top_profile[x] + k, mo[rnd.randint(0, 2)])
    return cv


def thorn_barrier():
    cv = Canvas(40, 26)
    w = MAT["wood"]
    rnd = random.Random(4)
    for i in range(7):
        x = 3 + i * 5 + rnd.randint(-1, 1)
        top = 4 + rnd.randint(0, 5)
        ang = rnd.uniform(-0.25, 0.25)
        for y in range(top, 24):
            xx = x + (y - top) * ang
            cv.p(xx, y, w[1]); cv.p(xx + 1, y, w[0])
        cv.p(x, top - 1, w[2]); cv.p(x, top - 2, MAT["bone"][1])
    for y in (12, 17):
        cv.line(1, y, 38, y + rnd.randint(-2, 2), hexc("3a2a1a"))
        for x in range(2, 38, 3):
            cv.p(x, y - 1, hexc("2a1e14"))
    return cv


def gate(open_):
    cv = Canvas(44, 46)
    st = ramp("22222a", "3a3a44", "54545e")
    cv.shaded(0, 6, 8, 40, st, 2, 2, 0)
    cv.shaded(36, 6, 8, 40, st, 2, 2, 0)
    cv.shaded(0, 2, 44, 7, st, 1, 2, 2)
    ir = MAT["iron_dark"]
    bottom = 14 if open_ else 44
    for x in range(10, 36, 4):
        cv.rect(x, 9, 2, bottom - 9, ir[1]); cv.rect(x, 9, 1, bottom - 9, ir[2])
    for y in range(12, bottom, 7):
        cv.rect(8, y, 28, 1, ir[1])
    for x in range(10, 36, 4):
        cv.p(x, bottom, ir[2]); cv.p(x, bottom + 1, ir[0])
    return cv


def small_props():
    out = {}
    # grass tufts
    for i in range(4):
        cv = Canvas(10, 9)
        rnd = random.Random(i)
        g = [hexc("1e2c14"), hexc("2e4220"), hexc("47602c"), hexc("6a7a3a")]
        for k in range(6):
            x = rnd.randint(1, 8); hgt = rnd.randint(3, 8)
            for y in range(hgt):
                cv.p(x + (y // 3) * rnd.choice([-1, 0, 1]), 8 - y, g[min(3, y // 2 + (1 if x < 5 else 0))])
        out[f"grass_{i}"] = cv
    # reeds
    cv = Canvas(10, 16)
    for k, x in enumerate([2, 4, 6, 8]):
        h = 10 + (k * 3) % 5
        cv.line(x, 15, x + (k % 2), 15 - h, hexc("4a5a2a"))
        cv.rect(x + (k % 2), 15 - h, 1, 3, hexc("5a3a20"))
    out["reeds"] = cv
    # mushrooms (red, like the references)
    for i in range(2):
        cv = Canvas(12, 9)
        rnd = random.Random(10 + i)
        for k in range(3):
            x = 2 + k * 3 + rnd.randint(0, 1); h = rnd.randint(2, 4)
            cv.rect(x, 8 - h, 1, h, MAT["bone"][2])
            cv.rect(x - 1, 8 - h - 1, 3, 1, hexc("a02018")); cv.p(x, 8 - h - 2, hexc("c83a28")); cv.p(x - 1, 8 - h - 1, hexc("6e1410"))
        out[f"mushrooms_{i}"] = cv
    # ferns
    cv = Canvas(18, 10)
    for k in range(5):
        a = math.pi + k * math.pi / 4
        for r in range(8):
            x = 9 + math.cos(a) * r; y = 9 + math.sin(a) * r * 0.8
            cv.p(x, y, hexc("2e4a2a") if r % 2 else hexc("466a3a"))
    out["fern"] = cv
    # bones
    cv = Canvas(12, 6)
    cv.line(1, 3, 9, 2, MAT["bone"][2]); cv.p(0, 2, MAT["bone"][2]); cv.p(0, 4, MAT["bone"][2]); cv.p(10, 1, MAT["bone"][2]); cv.p(10, 3, MAT["bone"][2])
    cv.shaded(7, 3, 4, 3, MAT["bone"], 1, 1, 0)
    out["bones"] = cv
    # starlight moth (death drop), 2 frames
    for f in range(2):
        cv = Canvas(12, 10)
        wing = 3 if f == 0 else 2
        c1, c2 = hexc("e8ecff"), hexc("a0a8e0")
        cv.rect(5, 3, 2, 5, c2)
        cv.ellipse(3, 4, wing, 2, c1); cv.ellipse(8, 4, wing, 2, c1)
        cv.p(5, 2, c1); cv.p(6, 2, c1)
        out[f"moth_{f}"] = cv
    # loot bag
    cv = Canvas(10, 10)
    cv.shaded(1, 3, 8, 7, MAT["leather"], 1, 1, 1)
    cv.rect(3, 1, 4, 2, MAT["leather"][1]); cv.rect(3, 3, 4, 1, MAT["gold"][1])
    out["loot"] = cv
    # Nana ghost: a small translucent old woman with a bun and shawl
    cv = Canvas(14, 20)
    g = [(110, 140, 200, 150), (160, 190, 240, 170), (210, 230, 255, 190)]
    cv.ellipse(7, 3, 2, 2, g[1])                     # bun
    cv.shaded(4, 4, 6, 5, g, 1, 1, 0)                # face
    cv.p(5, 6, (40, 50, 90, 200)); cv.p(8, 6, (40, 50, 90, 200))
    cv.shaded(2, 9, 10, 6, g, 2, 2, 0)               # shawl
    for y in range(15, 20):
        for x in range(3 + (y - 15) // 2, 11 - (y - 15) // 2):
            cv.p(x, y, (110, 140, 200, max(40, 150 - (y - 15) * 25)))
    out["nana"] = cv
    # brazier
    for f in range(3):
        cv = Canvas(14, 22)
        cv.shaded(3, 10, 8, 4, MAT["iron_dark"], 1, 1, 1)
        cv.line(4, 14, 2, 21, MAT["iron_dark"][1]); cv.line(9, 14, 11, 21, MAT["iron_dark"][1]); cv.line(7, 14, 7, 21, MAT["iron_dark"][1])
        fl = [hexc("d24a10"), hexc("f08a24"), hexc("ffd060")]
        for y in range(2, 10):
            t = (10 - y) / 8; half = (1 - t) * 3.5 + 0.5; sway = math.sin(f * 2 + y) * t
            for x in range(int(-half), int(half) + 1):
                cv.p(7 + x + sway, y, fl[min(2, int((1 - abs(x) / max(half, 1)) * 2 + (1 - t)))])
        out[f"brazier_{f}"] = cv
    return out


def main():
    manifest = {"characters": {}, "props": {}}
    for name, (spec, fw, fh) in CHARACTERS.items():
        manifest["characters"][name] = build_character(name, spec, fw, fh)
    props = {}
    for i in range(4):
        props[f"pine_{i}"] = pine(i + 1, 52 + (i % 2) * 8, 88 + (i % 3) * 10)
    for i in range(2):
        props[f"dead_tree_{i}"] = dead_tree(i + 3)
    for i in range(3):
        props[f"rock_{i}"] = rock(i, 26 - i * 4, 18 - i * 3)
    props["standing_stone"] = standing_stone()
    props["moth_shrine"] = moth_shrine()
    props["gibbet"] = gibbet()
    for i in range(3):
        props[f"corpse_{i}"] = corpse(i)
    for i in range(3):
        props[f"ruin_wall_{i}"] = ruin_wall(i + 1)
    props["thorns"] = thorn_barrier()
    props["gate_closed"] = gate(False)
    props["gate_open"] = gate(True)
    for f in range(4):
        props[f"campfire_{f}"] = campfire(f)
    for f in range(3):
        props[f"torch_{f}"] = torch(f)
    props.update(small_props())
    no_outline = {"nana", "moth_0", "moth_1"}
    for name, cv in props.items():
        save(cv, "prop_" + name, outline=name not in no_outline and not name.startswith(("campfire", "torch", "brazier")))
        manifest["props"][name] = {"w": cv.w, "h": cv.h}
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("characters:", list(manifest["characters"]), "props:", len(manifest["props"]))


if __name__ == "__main__":
    main()
