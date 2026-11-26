"""Hollowmoth character renderer: Diablo-2-style pre-rendered pixel sprites.

Each character is a little 3D puppet: a skeleton posed per animation frame,
dressed in capsules and spheres (body, clothes, hair, weapons). Every frame is
rasterised as depth-tested capsule impostors, lit from the upper left with
hue-shifted colour ramps, then given a selective outline and inner contour
lines so it reads as hand-made pixel art.

Output per character: a sheet with one row per view (down, side, up) and
columns idle(4) walk(8) attack(6) hurt(2) cast(4) death(6), plus manifest
entries. Sprites are drawn at 2x density (shown at scale 0.5 in Godot).
"""
import colorsys, json, math, os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

PITCH = math.radians(32)
F = 2.0          # extra density on top of the 2x design units -> 4x total (1 texel = 1 screen px at 1080p)
RAMP_N = 8
METALS = {"steel", "silver", "iron", "gold", "mail"}
LIGHT = np.array([-0.55, -0.62, 0.56])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
ANIMS = [("idle", 4), ("walk", 8), ("attack", 6), ("hurt", 2), ("cast", 4), ("death", 6)]
VIEWS = [("down", 0.0), ("side", 90.0), ("up", 180.0)]

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0) - 0.47


# ------------------------------------------------------------------ colour
def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def make_ramp(base, n=8, hue_shift=0.05, spread=0.42):
    """Hue-shifted ramp: shadows drift cool/purple, highlights warm."""
    r, g, b = hexrgb(base)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(n):
        t = i / (n - 1) - 0.5            # -0.5 .. 0.5
        hh = (h - t * hue_shift * 2) % 1.0 if s > 0.08 else h
        ss = min(1, max(0, s * (1.0 - t * 0.5) + (0.05 if t < 0 else -0.02)))
        vv = min(1, max(0.02, v * (1 + t * spread * 2.2)))
        rr, gg, bb = colorsys.hsv_to_rgb(hh if t >= 0 else (h + abs(t) * 0.09) % 1.0, ss, vv)
        out.append((int(rr * 255), int(gg * 255), int(bb * 255)))
    return out


MATS = {}


def mat(name, base, tex="none", tex_amp=0.0, emissive=False, spread=0.42):
    MATS[name] = {"ramp": make_ramp(base, spread=spread), "tex": tex, "amp": tex_amp, "emissive": emissive}


# skins
mat("skin_human", "#9c6a4e", spread=0.36); mat("skin_elf", "#b8987c", spread=0.36); mat("skin_dwarf", "#9a6248", spread=0.36); mat("skin_pale", "#c9c3c6", spread=0.3)
mat("skin_ghoul", "#6c7a5c", "noise", 0.18); mat("skin_brute", "#86624c", "noise", 0.12); mat("skin_shadow", "#241a2a")
# cloth and gear
mat("fur", "#6c4c32", "noise", 0.45); mat("leather", "#5a3e2a", "leather", 0.12); mat("leather_red", "#6a2c1e", "noise", 0.1)
mat("cloth_green", "#33503a", "fold", 0.2); mat("cloth_moss", "#465630", "fold", 0.2); mat("cloth_black", "#1e1e2a", "fold", 0.25, spread=0.6)
mat("robe_purple", "#35204a", "fold", 0.25, spread=0.55); mat("rag", "#4a3e2e", "noise", 0.35)
mat("mail", "#646a74", "mail", 0.5); mat("steel", "#666d78", "none", 0.0, spread=0.5); mat("iron", "#3e3e48", "plate", 0.3, spread=0.5)
mat("silver", "#a8aab4", spread=0.5); mat("gold", "#b08428"); mat("wood", "#5a3c24", "grain", 0.2); mat("bone", "#c4bba0")
mat("string", "#d8d4c0"); mat("herb", "#4a6a2e", "noise", 0.2); mat("feather", "#d8d0c0"); mat("feather_red", "#8a2a1a")
mat("lips", "#6a3a32"); mat("teeth", "#d8d0b0"); mat("rope", "#6a5a3a", "grain", 0.25)
# hair
mat("hair_brown", "#4e2c18", "strand", 0.3); mat("hair_purple", "#5a3a76", "strand", 0.3); mat("hair_orange", "#b0501a", "strand", 0.35)
mat("hair_white", "#d0d0dc", "strand", 0.25, spread=0.3); mat("hair_black", "#1c1818", "strand", 0.2)
# eyes and glows
mat("eye", "#140c0c", spread=0.0); mat("eye_glow_violet", "#c8a0ff", emissive=True); mat("eye_glow_red", "#ff5030", emissive=True)
mat("eye_glow_yellow", "#d8e078", emissive=True); mat("orb", "#a060ff", emissive=True); mat("moth_glow", "#e0e6ff", emissive=True)
mat("hood_in", "#120c16")


# ------------------------------------------------------------------ math
def rot_x(v, a):
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    return np.array([x, y * c - z * s, y * s + z * c])


def rot_y(v, a):
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    return np.array([x * c + z * s, y, -x * s + z * c])


def rot_z(v, a):
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    return np.array([x * c - y * s, x * s + y * c, z])


def V(*a):
    return np.array(a, dtype=float)


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ puppet
class Puppet:
    """Builds joints from a pose, then dresses them in primitives."""

    def __init__(self, spec):
        self.s = spec

    def joints(self, pose):
        S = self.s
        leg = S["leg"]; thigh = leg * 0.52; shin = leg * 0.48
        torso = S["torso"]
        J = {}
        pel = V(0, leg + pose.get("bob", 0.0), 0)
        J["pelvis"] = pel
        lean = math.radians(pose.get("lean", 0.0) + S.get("hunch", 0.0))
        twist = math.radians(pose.get("twist", 0.0))
        spine = rot_y(rot_x(V(0, 1, 0), lean), twist)
        J["chest"] = pel + spine * torso
        J["neck"] = J["chest"] + spine * S["neck"]
        J["head"] = J["neck"] + spine * S["head"] * 0.55 + rot_y(V(0, 0, 1), twist) * S.get("head_fwd", 0.0)
        right = rot_y(V(1, 0, 0), twist)
        for side, sgn in (("L", -1), ("R", 1)):
            hip = pel + V(sgn * S["hip_w"], -1.0, 0)
            a = math.radians(pose.get("hip" + side, 0.0))
            thigh_dir = rot_x(V(0, -1, 0), -a)
            knee = hip + thigh_dir * thigh
            kb = math.radians(pose.get("knee" + side, 4.0))
            shin_dir = rot_x(thigh_dir, kb)
            foot = knee + shin_dir * shin
            J["hip" + side], J["knee" + side], J["foot" + side] = hip, knee, foot
            sh = J["chest"] + right * sgn * S["sh_w"] - spine * 1.5
            pitch = math.radians(pose.get("sh" + side, 0.0))
            roll = math.radians(pose.get("roll" + side, 8.0)) * sgn
            up_dir = rot_z(rot_x(rot_y(V(0, -1, 0), twist), -pitch), roll)
            elbow = sh + up_dir * S["arm"] * 0.5
            eb = math.radians(pose.get("elb" + side, 12.0))
            fore = rot_x(up_dir, -eb)
            hand = elbow + fore * S["arm"] * 0.5
            J["sh" + side], J["elb" + side], J["hand" + side] = sh, elbow, hand
            J["fore" + side] = fore
        J["spine"] = spine
        J["right"] = right
        J["fwd"] = rot_y(rot_x(V(0, 0, 1), lean), twist)
        # whole-body fall (death): rotate everything about the feet
        fall = math.radians(pose.get("fall", 0.0))
        if fall:
            sideways = pose.get("fall_axis", "x") == "z"
            rot = (lambda v: rot_z(v, fall)) if sideways else (lambda v: rot_x(v, -fall))
            slide = V(-pose.get("slide", 0.0), 0, 0) if sideways else V(0, 0, -pose.get("slide", 0.0))
            for k, v in list(J.items()):
                if k in ("spine", "right", "fwd") or k.startswith("fore"):
                    J[k] = rot(v)
                else:
                    J[k] = rot(v) + V(0, pose.get("drop", 0.0), 0) + slide
            # keep the body centred on the frame as it falls
            k = min(1.0, fall / math.radians(60))
            c = J["pelvis"] * np.array([1.0, 0.0, 1.0]) * k * 0.9
            for key in list(J.keys()):
                if not (key in ("spine", "right", "fwd") or key.startswith("fore")):
                    J[key] = J[key] - c
        return J

    def dress(self, J, pose):
        S = self.s
        P = []

        def cap(a, b, ra, rb, m, g):
            P.append((np.array(a, float), np.array(b, float), float(ra), float(rb), m, g))

        def sph(c, r, m, g):
            cap(c, c, r, r, m, g)

        skin = S["skin"]
        legm = S.get("legs", "leather"); boots = S.get("boots", "leather")
        top = S["top"]; arms = S.get("arms", top)
        # legs
        for side in "LR":
            g = "leg" + side
            cap(J["hip" + side], J["knee" + side], S["thigh_r"], S["thigh_r"] * 0.85, legm, g)
            cap(J["knee" + side], J["foot" + side] + V(0, 1.5, 0), S["thigh_r"] * 0.8, S["thigh_r"] * 0.7, boots if S.get("tall_boots") else legm, g)
            fwd = J["fwd"] * np.array([1, 0, 1])
            cap(J["foot" + side] + V(0, 1.2, 0), J["foot" + side] + V(0, 1.0, 0) + fwd * 3.0, 1.9, 1.7, boots, g)
        # torso
        pel, chest = J["pelvis"], J["chest"]
        cap(pel + V(0, 1, 0), chest - J["spine"] * 1.0, S["waist_r"], S["chest_r"], top, "torso")
        if S.get("belly"):
            sph(pel + J["spine"] * S["torso"] * 0.4 + J["fwd"] * S["waist_r"] * 0.45, S["waist_r"] * 1.12, S.get("belly_m", skin), "torso")
        if S.get("bare_chest"):
            sph(chest - J["spine"] * 3 + J["fwd"] * (S["chest_r"] * 0.35), S["chest_r"] * 0.78, skin, "torso")
        if S.get("belt"):
            cap(pel + V(0, 1.5, 0) - J["right"] * S["waist_r"] * 0.2, pel + V(0, 1.5, 0) + J["right"] * S["waist_r"] * 0.2, S["waist_r"] + 0.6, S["waist_r"] + 0.6, S["belt"], "torso")
        if S.get("robe"):
            hem = (J["footL"] + J["footR"]) / 2 + V(0, 2.5, 0)
            cap(pel + V(0, 2, 0), hem, S["waist_r"] + 0.5, S["robe_r"], S["robe"], "torso")
        if S.get("skirt"):
            cap(pel + V(0, 1.5, 0), pel - V(0, S["leg"] * 0.35, 0), S["waist_r"] + 0.8, S["waist_r"] + 2.2, S["skirt"], "torso")
        if S.get("cape"):
            back = -J["fwd"] * (S["chest_r"] * 0.85)
            for k in (-1, 0, 1):
                off = J["right"] * k * S["chest_r"] * 0.55
                cap(chest + back + off - J["spine"] * 1.5, pel + back * 1.15 + off - V(0, S["leg"] * 0.55, 0) - J["fwd"] * pose.get("cape_flow", 0.0), 2.6, 3.2, S["cape"], "cape")
        if S.get("pauldrons"):
            for side in "LR":
                sph(J["sh" + side] + V(0, 1.2, 0), S["pauldrons_r"], S["pauldrons"], "torso")
        # arms (back arm first is irrelevant: depth test handles it)
        for side in "LR":
            g = "arm" + side
            cap(J["sh" + side], J["elb" + side], S["arm_r"], S["arm_r"] * 0.9, arms, g)
            cap(J["elb" + side], J["hand" + side], S["arm_r"] * 0.88, S["arm_r"] * 0.75, S.get("fore", arms), g)
            sph(J["hand" + side] + J["fore" + side] * 0.8, S["arm_r"] * 0.85, S.get("hands", skin), g)
        # neck and head
        cap(chest, J["neck"], S["neck_r"], S["neck_r"], skin, "head")
        head = J["head"]
        hr = S["head"] * 0.5
        hood = S.get("hood")
        if hood:
            sph(head + V(0, 0.6, 0) - J["fwd"] * 0.6, hr * 1.38, hood, "head")
            sph(head + J["fwd"] * (hr * 0.55), hr * 0.82, "hood_in", "face")
            cap(head + V(0, hr * 1.1, 0) - J["fwd"] * 1.0, head + V(0, hr * 1.9, 0) - J["fwd"] * 3.0, hr * 0.6, 0.6, hood, "head")
        else:
            sph(head, hr, skin, "head")
        f = J["fwd"]; r = J["right"]; up = J["spine"]
        eye = S.get("eye_m", "eye")
        for sgn in (-1, 1):
            sph(head + f * (hr * (0.86 if not hood else 0.95)) + r * sgn * hr * 0.36 + up * hr * 0.05, 0.72 if not hood else 0.85, eye, "face")
        if S.get("ears"):
            for sgn in (-1, 1):
                cap(head + r * sgn * hr * 0.85, head + r * sgn * hr * 1.65 + up * hr * 0.7 - f * 0.8, 1.2, 0.5, skin, "head")
        if S.get("hair") and not hood:
            hm = S["hair"]
            sph(head + up * hr * 0.35 - f * hr * 0.25, hr * 1.02, hm, "hair")
            if S.get("long_hair"):
                cap(head - f * hr * 0.4, head - f * hr * 0.75 - up * hr * 2.2, hr * 0.95, hr * 0.85, hm, "hair")
            if S.get("braid"):
                cap(head - f * hr * 0.8, head - f * hr * 1.3 - up * hr * 2.5, 1.4, 1.0, hm, "hair")
        if S.get("beard"):
            cap(head + f * hr * 0.55 - up * hr * 0.3, head + f * hr * 0.85 - up * hr * 1.6, hr * 0.85, hr * 0.55, S["beard"], "beard")
            cap(head + f * hr * 0.85 - up * hr * 1.6, head + f * hr * 0.9 - up * hr * 2.6, hr * 0.5, 0.9, S["beard"], "beard")
        if S.get("helm"):
            sph(head + up * hr * 0.4 - f * 0.2, hr * 1.12, S["helm"], "helm")
            cap(head + f * hr * 1.0 + up * hr * 0.6, head + f * hr * 1.08 - up * hr * 0.2, 0.7, 0.6, S["helm"], "helm")
            if S.get("spike"):
                cap(head + up * hr * 1.2, head + up * hr * 2.6, 1.6, 0.4, S["helm"], "helm")
        self._details(J, pose, cap, sph, head, hr, f, r, up)
        self._weapon(J, pose, cap, sph)
        return P

    def _details(self, J, pose, cap, sph, head, hr, f, r, up):
        S = self.s
        skin = S["skin"]
        hood = S.get("hood")
        pel, chest, spine = J["pelvis"], J["chest"], J["spine"]
        # face: nose, brows, mouth
        if not hood and not S.get("no_face"):
            sph(head + f * hr * 0.98 - up * hr * 0.12, hr * 0.17, skin, "face")
            brow = S.get("hair", S.get("beard", "hair_black"))
            for sgn in (-1, 1):
                cap(head + f * hr * 0.86 + r * sgn * hr * 0.18 + up * hr * 0.27,
                    head + f * hr * 0.8 + r * sgn * hr * 0.55 + up * hr * 0.33, hr * 0.09, hr * 0.07, brow, "face")
            if not S.get("beard"):
                cap(head + f * hr * 0.9 - up * hr * 0.42 - r * hr * 0.2, head + f * hr * 0.9 - up * hr * 0.42 + r * hr * 0.2,
                    hr * 0.07, hr * 0.07, "lips", "face")
        # fingers
        for side in "LR":
            hd = J["hand" + side] + J["fore" + side] * 0.8
            fd = J["fore" + side]
            for k in (-1, 0, 1):
                o = hd + fd * S["arm_r"] * 0.6 + r * k * S["arm_r"] * 0.45
                cap(o, o + fd * S["arm_r"] * 0.9, S["arm_r"] * 0.25, S["arm_r"] * 0.2, S.get("hands", skin), "arm" + side)
            if S.get("bracers"):
                cap(J["elb" + side] + fd * 2.5, J["hand" + side] - fd * 0.5, S["arm_r"] * 1.05, S["arm_r"] * 0.95, S["bracers"], "arm" + side)
        # boot cuffs
        for side in "LR":
            if S.get("cuffs"):
                k = J["knee" + side]
                sph(k + (J["foot" + side] - k) * 0.35, S["thigh_r"] * 0.95, S["cuffs"], "leg" + side)
        # belt buckle and pouches
        if S.get("belt"):
            sph(pel + V(0, 1.5, 0) + f * (S["waist_r"] + 0.4), 1.2, "gold", "torso")
            for k, sgn in enumerate((-1, 1)):
                if S.get("pouches"):
                    sph(pel + V(0, 0.4, 0) + r * sgn * S["waist_r"] * 0.85 + f * S["waist_r"] * 0.35, 1.9, "leather", "torso")
        # bandolier with herb pouches (Puck)
        if S.get("bandolier"):
            a = J["shL"] + V(0, 1, 0) + f * S["chest_r"] * 0.5
            b = pel + r * S["waist_r"] * 0.9 + f * S["waist_r"] * 0.6 + V(0, 2, 0)
            cap(a, b, 0.8, 0.8, "leather", "strap")
            for t in (0.3, 0.55, 0.8):
                sph(a + (b - a) * t + f * 1.2, 1.5, "herb" if t != 0.55 else "leather", "strap")
        # quiver on the back (Brokk)
        if S.get("quiver"):
            qa = chest - f * S["chest_r"] * 0.95 + r * S["chest_r"] * 0.4 + up * 4
            qb = pel - f * S["waist_r"] * 0.9 - r * S["waist_r"] * 0.3 + up * 1
            cap(qa, qb, 2.4, 2.0, "leather", "quiver")
            for k in range(4):
                o = qa + r * (k - 1.5) * 0.9 + up * 1.5
                cap(o, o + up * 3.5 - f * 0.6, 0.35, 0.35, "wood", "quiver")
                cap(o + up * 3.0, o + up * 5.5 - f * 0.4, 0.9, 0.3, "feather" if k % 2 else "feather_red", "quiver")
        # fur tufts on pauldrons (Average)
        if S.get("pauldrons") == "fur":
            for side in "LR":
                for k in range(3):
                    sph(J["sh" + side] + V(0, 2.4, 0) + f * (k - 1) * 1.8, 2.0, "fur", "torso")
        # tooth necklace (Average) / bone necklace (cultist)
        if S.get("necklace"):
            for k in range(7):
                a = (k - 3) / 3 * 1.1
                o = chest + up * 1.5 + f * (S["chest_r"] * 0.85) * math.cos(a) + r * S["chest_r"] * 0.7 * math.sin(a) - up * abs(math.sin(a)) * -1.5 - up * 2
                sph(o, 0.75, S["necklace"], "neck")
        # silver collar + moth pendant (Sael)
        if S.get("pendant"):
            sph(chest + up * 1.0 + f * (S["chest_r"] * 0.9), 1.3, "silver", "neck")
            cap(chest + up * 3 + f * S["chest_r"] * 0.6 - r * 3, chest + up * 3 + f * S["chest_r"] * 0.6 + r * 3, 0.6, 0.6, "silver", "neck")
            for sgn in (-1, 1):
                sph(chest + up * 1.0 + f * (S["chest_r"] * 0.95) + r * sgn * 1.4, 0.8, "moth_glow", "neck")
        # robe trim lines (Sael, cultist)
        if S.get("robe") and S.get("trim"):
            hem = (J["footL"] + J["footR"]) / 2 + V(0, 2.5, 0)
            cap(chest - up * 2 + f * S["chest_r"] * 0.95, hem + f * S["robe_r"] * 0.98, 0.45, 0.6, S["trim"], "trim")
        # ghoul ribs
        if S.get("ribs"):
            for k in range(4):
                o = chest - up * (2 + k * 2.2) + f * S["chest_r"] * 0.88
                cap(o - r * S["chest_r"] * 0.6, o + r * S["chest_r"] * 0.6, 0.45, 0.45, "skin_shadow", "ribs")
        # beard braids with gold rings (Brokk)
        if S.get("beard_braids"):
            for sgn in (-1, 1):
                a = head + f * hr * 0.85 - up * hr * 1.4 + r * sgn * hr * 0.35
                cap(a, a - up * hr * 1.4, 1.0, 0.7, S["beard"], "beard")
                sph(a - up * hr * 0.9, 1.1, "gold", "beard")
        # iron brother: rivets and visor slit, tattered cape
        if S.get("rivets"):
            for k in range(6):
                a = (k - 2.5) / 2.5 * 1.0
                sph(chest - up * 3 + f * S["chest_r"] * math.cos(a) * 0.96 + r * S["chest_r"] * math.sin(a) * 0.96, 0.9, "steel", "torso")
                sph(pel + up * 3 + f * S["waist_r"] * math.cos(a) * 0.98 + r * S["waist_r"] * math.sin(a) * 0.98, 0.8, "steel", "torso")
            cap(head + f * hr * 1.05 + up * hr * 0.1 - r * hr * 0.5, head + f * hr * 1.05 + up * hr * 0.1 + r * hr * 0.5, 0.7, 0.7, "hood_in", "visor")
            back = -f * S["chest_r"] * 0.9
            for k in (-1, 0, 1):
                cap(chest + back + r * k * 4 - up * 2, pel + back * 1.1 + r * k * 4.5 - up * S["leg"] * 0.55, 3.0, 2.2, "leather_red", "cape")
        # rope belt
        if S.get("rope"):
            cap(pel + V(0, 2.5, 0) - r * S["waist_r"], pel + V(0, 2.5, 0) + r * S["waist_r"], S["waist_r"] + 0.7, S["waist_r"] + 0.7, "rope", "torso")
            cap(pel + V(0, 2, 0) + f * S["waist_r"], pel - V(0, 5, 0) + f * (S["waist_r"] + 1), 0.6, 0.5, "rope", "torso")

    def _weapon(self, J, pose, cap, sph):
        S = self.s
        w = S.get("weapon")
        if not w:
            return
        hand = J["handR"] + J["foreR"] * 0.8
        wa = math.radians(pose.get("wpn", 0.0))
        # weapon direction: forearm direction bent forward by wpn angle
        d = J["foreR"]
        axis = -J["right"]
        d = d * math.cos(wa) + np.cross(axis, d) * math.sin(wa) + axis * np.dot(axis, d) * (1 - math.cos(wa))
        d = d / np.linalg.norm(d)
        side = np.cross(d, J["fwd"])
        if np.linalg.norm(side) < 1e-3:
            side = J["right"]
        side = side / np.linalg.norm(side)
        if w == "axe":
            L = 30
            cap(hand - d * 4, hand + d * L, 0.9, 0.9, "wood", "wpn")
            for k in range(5):
                o = hand - d * 3 + d * k * 1.4
                cap(o, o + d * 0.7, 1.15, 1.15, "leather", "wpn")
            sph(hand + d * (L - 5), 1.3, "iron", "wpn")
            for k in range(4):
                o = hand + d * (L - 2 - k * 1.6)
                cap(o, o + side * 7.5 - d * 1.5, 1.3, 2.6, "steel", "wpn")
        elif w == "rapier":
            cap(hand - d * 2.5, hand + d * 30, 0.55, 0.35, "silver", "wpn")
            cap(hand + d * 0.6 - side * 3, hand + d * 0.6 + side * 3, 0.7, 0.7, "gold", "wpn")
            sph(hand - d * 0.4, 1.4, "gold", "wpn")
            sph(hand - d * 3.0, 1.2, "gold", "wpn")
            prev = None
            for k in range(9):
                a = k / 8 * math.pi
                o = hand + d * (1.0 + math.sin(a) * 2.5) + side * math.cos(a) * 2.8
                if prev is not None:
                    cap(prev, o, 0.35, 0.35, "gold", "wpn")
                prev = o
        elif w == "starknife":
            c = hand + d * 2.5
            sph(c, 1.4, "silver", "wpn")
            for k in range(4):
                a = k * math.pi / 2 + 0.4
                v = side * math.cos(a) + np.cross(d, side) * math.sin(a)
                cap(c, c + v * 5.5, 1.0, 0.3, "silver", "wpn")
        elif w == "claws":
            for k in (-1, 0, 1):
                cap(hand + d * 1.0 + side * k * 1.2, hand + d * 6.0 + side * k * 1.8, 0.6, 0.3, "bone", "wpn")
        elif w == "staff":
            up = J["spine"]
            cap(hand - up * 16, hand + up * 18, 0.9, 0.9, "wood", "wpn")
            for k in range(3):
                sph(hand + up * (12 + k * 2.2), 1.15, "bone", "wpn")
            for k in range(4):
                a = k * math.pi / 2
                cap(hand + up * 17.5, hand + up * 22 + (side * math.cos(a) + J["fwd"] * math.sin(a)) * 3.2, 0.5, 0.3, "bone", "wpn")
            sph(hand + up * 20, 2.6, "orb", "wpn")
        elif w == "club":
            cap(hand - d * 3, hand + d * 26, 1.2, 4.6, "wood", "wpn")
            for k in range(5):
                a = k * 1.3
                o = hand + d * (20 + k)
                cap(o, o + (side * math.cos(a) + J["fwd"] * math.sin(a)) * 5.5, 0.9, 0.3, "bone", "wpn")
        elif w == "hammer":
            L = 46
            cap(hand - d * 8, hand + d * L, 1.4, 1.4, "wood", "wpn")
            cap(hand + d * L - side * 9, hand + d * L + side * 9, 5.6, 5.6, "iron", "wpn")
            for k in (-6, 0, 6):
                cap(hand + d * L + side * (k - 0.6), hand + d * L + side * (k + 0.6), 5.9, 5.9, "steel", "wpn")
            cap(hand + d * L + side * 9.5, hand + d * L + side * 12.5, 4.2, 2.0, "steel", "wpn")
        elif w == "bow":
            # bow in the LEFT hand, held upright; string to the right hand when drawn
            hl = J["handL"] + J["foreL"] * 0.8
            up = J["spine"]
            prev = None
            pts = []
            for k in range(-6, 7):
                t = k / 6
                p = hl + up * (t * 17) + J["fwd"] * (math.cos(t * math.pi / 2) * 5.0)
                pts.append(p)
                if prev is not None:
                    cap(prev, p, 1.1, 1.1, "wood", "wpn")
                prev = p
            pull = pose.get("pull", 0.0)
            mid = (pts[0] + pts[-1]) / 2 - J["fwd"] * pull
            cap(pts[0], mid, 0.35, 0.35, "string", "wpn")
            cap(mid, pts[-1], 0.35, 0.35, "string", "wpn")
            if pose.get("arrow"):
                cap(mid, mid + J["fwd"] * 24, 0.45, 0.45, "wood", "wpn")
                cap(mid + J["fwd"] * 22, mid + J["fwd"] * 26, 1.0, 0.2, "steel", "wpn")


# ------------------------------------------------------------------ poses
def pose_for(spec, anim, i, n):
    p = {}
    w = spec.get("weapon")
    t = i / n
    ph = t * math.tau
    rest_wpn = spec.get("rest_wpn", 70.0)
    if anim == "idle":
        p["bob"] = -0.6 * (1 - math.cos(ph)) / 2
        p["shL"] = 6 + math.sin(ph) * 2; p["shR"] = 10 + math.sin(ph) * 2
        p["elbR"] = 30; p["wpn"] = rest_wpn
        p["kneeL"] = p["kneeR"] = 6
    elif anim == "walk":
        sw = 30.0
        p["hipL"] = math.sin(ph) * sw; p["hipR"] = -math.sin(ph) * sw
        p["kneeL"] = 8 + max(0.0, -math.sin(ph + 0.6)) * 45
        p["kneeR"] = 8 + max(0.0, math.sin(ph + 0.6)) * 45
        p["bob"] = -abs(math.cos(ph)) * 1.4 + 0.6
        p["shL"] = -math.sin(ph) * 24; p["shR"] = math.sin(ph) * 18 + 10
        p["elbL"] = 18; p["elbR"] = 30
        p["lean"] = 4
        p["wpn"] = rest_wpn
        p["cape_flow"] = 3 + math.sin(ph * 2) * 1.5
    elif anim == "attack":
        if w == "bow":
            draw = [0.0, 0.4, 0.8, 1.0, 0.2, 0.0][i]
            p["shL"] = 88; p["rollL"] = -4; p["elbL"] = 2
            p["shR"] = 70 + draw * 15; p["elbR"] = 40 + draw * 100; p["rollR"] = -20
            p["pull"] = draw * 9 if i < 4 else 0
            p["arrow"] = i < 4
            p["twist"] = 15
        elif w == "staff":
            p["shR"] = [40, 80, 120, 60, 40, 20][i]; p["elbR"] = 20
            p["shL"] = [10, 40, 90, 110, 60, 20][i]
            p["lean"] = [0, -4, -6, 8, 4, 0][i]
        else:
            # overhead diagonal swing: windup (0-2), strike (3), follow-through (4-5)
            sh = [40, 110, 160, 40, -10, 10][i]
            roll = [10, 30, 35, -10, -35, -10][i]
            p["shR"] = sh; p["rollR"] = roll
            p["elbR"] = [30, 40, 50, 6, 10, 25][i]
            p["wpn"] = [60, 50, 40, 15, 30, 55][i]
            p["twist"] = [0, 15, 22, -22, -30, -10][i]
            p["lean"] = [0, -4, -6, 12, 10, 4][i]
            p["shL"] = [0, -10, -15, 20, 25, 10][i]
            p["hipL"] = [0, 6, 10, 18, 14, 6][i]; p["hipR"] = [0, -6, -10, -16, -12, -4][i]
            p["kneeL"] = 20; p["kneeR"] = 14
            p["bob"] = [0, 0.5, 0.8, -1.8, -1.6, -0.6][i]
            p["cape_flow"] = [0, 1, 2, 6, 5, 3][i]
    elif anim == "hurt":
        p["lean"] = [-14, -8][i]; p["shL"] = [30, 18][i]; p["shR"] = [30, 20][i]
        p["rollL"] = 35; p["rollR"] = 35; p["elbR"] = 30; p["wpn"] = rest_wpn + 20
        p["bob"] = -0.8
        p["kneeL"] = 18; p["kneeR"] = 10
    elif anim == "cast":
        p["shL"] = 115 + math.sin(ph) * 8; p["shR"] = 115 - math.sin(ph) * 8
        p["rollL"] = -18; p["rollR"] = -18
        p["elbL"] = 25; p["elbR"] = 25
        p["lean"] = -6; p["wpn"] = 10
        p["bob"] = math.sin(ph) * 0.6
        p["glow"] = 0.6 + 0.4 * math.sin(ph)
    elif anim == "death":
        k = [0.0, 0.18, 0.45, 0.75, 0.95, 1.0][i]
        p["fall"] = 82 * k
        p["drop"] = -k * 1.5
        p["slide"] = k * 6
        p["lean"] = -12 * min(1, k * 3)
        p["shL"] = 40 + 60 * k; p["shR"] = 50 + 70 * k
        p["rollL"] = 40; p["rollR"] = 40
        p["kneeL"] = 30 * k; p["kneeR"] = 50 * k
        p["hipL"] = 20 * k; p["hipR"] = 5 * k
        p["wpn"] = rest_wpn + 60 * k
    return p


# ------------------------------------------------------------------ raster
def project(v, yaw, cx, gy):
    v = rot_y(v, math.radians(yaw)) * F
    x, y, z = v
    sx = cx + x
    sy = gy - y * math.cos(PITCH) + z * math.sin(PITCH)
    depth = y * math.sin(PITCH) + z * math.cos(PITCH)
    return sx, sy, depth


def render(prims, yaw, W, H, gy, glow=0.0, extra=None):
    cx = W / 2
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    zbuf = np.full((H, W), -1e9, np.float32)
    shade = np.zeros((H, W), np.float32)
    NX = np.zeros((H, W), np.float32); NY = np.zeros((H, W), np.float32); NZ = np.ones((H, W), np.float32)
    mid = np.full((H, W), -1, np.int32)
    gid = np.full((H, W), -1, np.int32)
    mat_names = list(MATS.keys())
    groups = {}
    for (a, b, ra, rb, m, g) in prims:
        ra, rb = ra * F, rb * F
        ax, ay, az = project(a, yaw, cx, gy)
        bx, by, bz = project(b, yaw, cx, gy)
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        if L2 < 1e-6:
            t = np.zeros_like(xs)
        else:
            t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / L2, 0, 1)
        px = ax + dx * t
        py = ay + dy * t
        ox, oy = xs - px, ys - py
        d2 = ox * ox + oy * oy
        r = ra + (rb - ra) * t
        inside = d2 < r * r
        if not inside.any():
            continue
        h = np.sqrt(np.maximum(r * r - d2, 0))
        depth = az + (bz - az) * t + h
        win = inside & (depth > zbuf)
        if not win.any():
            continue
        rr = np.maximum(r, 1e-3)
        nx, ny, nz = ox / rr, oy / rr, h / rr
        lam = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
        zbuf[win] = depth[win]
        shade[win] = lam[win]
        NX[win] = nx[win]; NY[win] = ny[win]; NZ[win] = nz[win]
        mid[win] = mat_names.index(m)
        gi = groups.setdefault(g, len(groups))
        gid[win] = gi
    # colour
    img = np.zeros((H, W, 4), np.uint8)
    bay = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    filled0 = mid >= 0
    # ambient occlusion: pixels sitting just behind nearby nearer surfaces get darker
    zf = np.where(filled0, zbuf, -1e9)
    near = zf.copy()
    for r in (2, 4, 6):
        for dy, dx in ((r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)):
            near = np.maximum(near, np.roll(np.roll(zf, dy, 0), dx, 1))
    ao = np.clip((near - zf - 2.0 * F) / (10.0 * F), 0, 1) * filled0
    shade = shade - ao * 0.55
    # specular for metal (view straight on, Blinn half vector)
    Hv = LIGHT + np.array([0, 0, 1.0]); Hv = Hv / np.linalg.norm(Hv)
    spec = np.clip(NX * Hv[0] + NY * Hv[1] + NZ * Hv[2], 0, 1) ** 24
    # warm firelight rim from the lower right
    rim = np.clip((NX * 0.7 + NY * 0.5) - NZ * 0.5, 0, 1)
    for mi, name in enumerate(mat_names):
        m = mid == mi
        if not m.any():
            continue
        M = MATS[name]
        ramp = M["ramp"]
        n = len(ramp)
        if M["emissive"]:
            v = np.full(m.sum(), n - 1 if glow == 0 else n - 1)
            idx = np.clip((shade[m] * 0.5 + 0.5) * 2 + n - 3, 0, n - 1).astype(int)
        else:
            s = shade[m] * 0.5 + 0.5
            s = s * 1.05 - 0.05
            if name in METALS:
                s = s + spec[m] * 0.45
            s = s + rim[m] * 0.12
            tex = M["tex"]
            amp = M["amp"]
            yy, xx = np.nonzero(m)
            if tex == "noise":
                rnd = np.sin(xx * 12.9898 + yy * 78.233) * 43758.5453
                s = s + (rnd - np.floor(rnd) - 0.5) * amp
                rnd2 = np.sin((xx // 2) * 7.13 + (yy // 3) * 3.7) * 9631.7
                s = s + (rnd2 - np.floor(rnd2) - 0.5) * amp * 0.6
            elif tex == "mail":
                ring = ((xx % 4 == 0) | (yy % 3 == 0)) & ~((xx % 4 == 0) & (yy % 3 == 0))
                s = s + np.where(ring, -amp * 0.55, amp * 0.15) + np.where(((xx + (yy // 3) * 2) % 4) == 2, amp * 0.35, 0)
            elif tex == "plate":
                s = s + np.where(yy % 6 == 0, -amp, 0) + np.where(yy % 6 == 1, amp * 0.6, 0)
            elif tex == "fold":
                s = s + np.where(((xx * 3 + yy) // 3) % 11 == 0, -amp, 0) + np.where(((xx * 3 + yy) // 3) % 11 == 1, amp * 0.4, 0)
                s = s + np.where((xx + yy) % 2 == 0, 0.015, -0.015)
            elif tex == "strand":
                s = s + np.where((xx + yy // 4) % 3 == 0, -amp, 0) + np.where((xx * 2 + yy // 5) % 7 == 0, amp * 0.7, 0)
            elif tex == "grain":
                s = s + np.where((yy + xx // 6) % 5 == 0, -amp, 0)
            elif tex == "leather":
                rnd = np.sin(xx * 3.17 + yy * 11.3) * 1531.3
                s = s + np.where((rnd - np.floor(rnd)) > 0.93, -amp * 2, 0)
            s = s + bay[m] * 0.09
            idx = np.clip(np.floor(s * n), 0, n - 1).astype(int)
        cols = np.array(ramp, np.uint8)[idx]
        img[m, :3] = cols
        img[m, 3] = 255
    filled = mid >= 0
    # inner contour: pixels just behind a nearer, different part get the darkest tone
    contour = np.zeros_like(filled)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb_z = np.roll(np.roll(zbuf, dy, 0), dx, 1)
        nb_g = np.roll(np.roll(gid, dy, 0), dx, 1)
        nb_f = np.roll(np.roll(filled, dy, 0), dx, 1)
        contour |= filled & nb_f & (nb_g != gid) & (nb_z > zbuf + 3.0)
    if contour.any():
        for mi, name in enumerate(mat_names):
            m = contour & (mid == mi)
            if m.any() and not MATS[name]["emissive"]:
                img[m, :3] = MATS[name]["ramp"][0]
    # selective outline: dark version of the neighbouring colour
    out = np.zeros((H, W), bool)
    col = np.zeros((H, W, 3), np.float32)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb_f = np.roll(np.roll(filled, dy, 0), dx, 1)
        nb_c = np.roll(np.roll(img[:, :, :3], dy, 0), dx, 1).astype(np.float32)
        take = (~filled) & nb_f & (~out)
        col[take] = nb_c[take]
        out |= take
    oc = (col * 0.22 + np.array([10, 6, 12])).clip(0, 255).astype(np.uint8)
    img[out, :3] = oc[out]
    img[out, 3] = 255
    if extra is not None:
        extra(img)
    nrm = np.zeros((H, W, 4), np.uint8)
    fm = img[:, :, 3] > 0
    nrm[:, :, 0] = np.clip(NX * 127.5 + 127.5, 0, 255).astype(np.uint8)
    nrm[:, :, 1] = np.clip(-NY * 127.5 + 127.5, 0, 255).astype(np.uint8)
    nrm[:, :, 2] = np.clip(NZ * 127.5 + 127.5, 0, 255).astype(np.uint8)
    nrm[:, :, 3] = 255
    nrm[~filled] = (128, 128, 255, 255)
    return img, nrm


# ------------------------------------------------------------------ specs
BASE = dict(leg=26, torso=17, neck=2.5, head=11, hip_w=3.2, sh_w=6.2, arm=20, thigh_r=2.8, arm_r=2.2,
            waist_r=5.0, chest_r=6.2, neck_r=2.0)


def spec(**kw):
    s = dict(BASE)
    s.update(kw)
    return s


CHARS = {
    "average": (spec(leg=28, torso=19, head=11.5, sh_w=8.0, chest_r=8.0, waist_r=6.6, thigh_r=3.5, arm_r=3.0, arm=22,
                     skin="skin_human", top="skin_human", arms="skin_human", bare_chest=True, legs="leather", boots="fur",
                     tall_boots=True, skirt="fur", belt="leather_red", pauldrons="fur", pauldrons_r=4.6, hair="hair_brown",
                     braid=True, weapon="axe", rest_wpn=28, necklace="teeth", bracers="leather", cuffs="fur", pouches=True), 104, 112),
    "puck": (spec(leg=26, torso=16, head=10.5, sh_w=5.6, chest_r=5.4, waist_r=4.4, thigh_r=2.5, arm_r=2.0,
                  skin="skin_elf", top="cloth_green", arms="cloth_green", legs="leather", boots="leather", tall_boots=True,
                  belt="leather", cape="cloth_moss", hair="hair_purple", ears=True, weapon="rapier", rest_wpn=25, bandolier=True, cuffs="leather", bracers="leather"), 96, 104),
    "brokk": (spec(leg=17, torso=16, head=11.5, sh_w=7.4, chest_r=7.6, waist_r=7.0, thigh_r=3.4, arm_r=2.9, arm=17,
                   skin="skin_dwarf", top="mail", arms="leather", legs="leather", boots="leather", tall_boots=True,
                   belt="leather_red", beard="hair_orange", helm="steel", hair="hair_orange", weapon="bow", quiver=True, beard_braids=True, bracers="leather", pouches=True, cuffs="leather"), 96, 96),
    "sael": (spec(leg=26, torso=16, head=10.5, sh_w=5.4, chest_r=5.2, waist_r=4.2, thigh_r=2.3, arm_r=1.9,
                  skin="skin_pale", top="cloth_black", arms="cloth_black", legs="cloth_black", boots="cloth_black",
                  robe="cloth_black", robe_r=9.0, belt="silver", hair="hair_white", long_hair=True, ears=True,
                  weapon="starknife", rest_wpn=30, pendant=True, trim="silver"), 96, 104),
    "ghoul": (spec(leg=22, torso=15, head=9.5, sh_w=5.6, chest_r=5.0, waist_r=3.6, thigh_r=2.2, arm_r=1.8, arm=24,
                   hunch=24, head_fwd=2.0, skin="skin_ghoul", top="skin_ghoul", arms="skin_ghoul", legs="rag", boots="skin_ghoul",
                   skirt="rag", hair="hair_black", eye_m="eye_glow_yellow", weapon="claws", rest_wpn=10, ribs=True, no_face=False), 92, 96),
    "cultist": (spec(leg=26, torso=17, head=11, sh_w=5.8, chest_r=5.6, waist_r=4.6, thigh_r=2.4, arm_r=2.1,
                     skin="skin_shadow", top="robe_purple", arms="robe_purple", legs="robe_purple", boots="leather",
                     robe="robe_purple", robe_r=9.5, hood="robe_purple", belt="bone", eye_m="eye_glow_violet",
                     weapon="staff", necklace="bone", trim="bone", rope=True), 96, 112),
    "brute": (spec(leg=32, torso=26, head=13, sh_w=12.0, chest_r=12.0, waist_r=10.5, thigh_r=5.2, arm_r=4.6, arm=30,
                   hunch=10, skin="skin_brute", top="skin_brute", arms="skin_brute", legs="leather", boots="skin_brute",
                   skirt="rag", belt="leather", belly=True, hair="hair_black", weapon="club", rest_wpn=30, rope=True, bracers="leather"), 136, 144),
    "iron_brother": (spec(leg=44, torso=36, head=16, neck=3, sh_w=17.0, chest_r=16.0, waist_r=13.0, thigh_r=7.0, arm_r=6.4,
                          arm=42, neck_r=4.5, skin="iron", top="iron", arms="iron", legs="iron", boots="iron", tall_boots=True,
                          belt="leather_red", pauldrons="steel", pauldrons_r=9.0, helm="steel", spike=True, skirt="leather_red",
                          eye_m="eye_glow_red", weapon="hammer", rest_wpn=30, rivets=True, no_face=True), 200, 208),
}


def build(name):
    sp, W, H = CHARS[name]
    W, H = int(W * F), int(H * F)
    pup = Puppet(sp)
    gy = H - int(14 * F)
    cols = sum(n for _, n in ANIMS)
    sheet = Image.new("RGBA", (W * cols, H * len(VIEWS)), (0, 0, 0, 0))
    nsheet = Image.new("RGBA", (W * cols, H * len(VIEWS)), (128, 128, 255, 255))
    meta = {"frame_w": W, "frame_h": H, "foot_y": gy, "anims": {}, "scale": 0.5 / F}
    for row, (view, yaw) in enumerate(VIEWS):
        col = 0
        for anim, n in ANIMS:
            meta["anims"][f"{anim}_{view}"] = {"row": row, "col": col, "count": n}
            for i in range(n):
                pose = pose_for(sp, anim, i, n)
                if anim == "death" and view != "side":
                    pose["fall_axis"] = "z"
                J = pup.joints(pose)
                prims = pup.dress(J, pose)
                if anim == "cast":
                    c = (J["handL"] + J["handR"]) / 2 + J["fwd"] * 3
                    prims.append((c, c, 2.0 + pose["glow"] * 2.5, 2.0 + pose["glow"] * 2.5, "moth_glow", "glow"))
                img, nrm = render(prims, yaw, W, H, gy)
                if anim == "attack" and i == 3 and sp.get("weapon") not in ("bow", "staff"):
                    _smear(img, pup, sp, yaw, W, H, gy)
                sheet.paste(Image.fromarray(img, "RGBA"), ((col + i) * W, row * H))
                nsheet.paste(Image.fromarray(nrm, "RGBA"), ((col + i) * W, row * H))
            col += n
    sheet.save(os.path.join(OUT, f"{name}.png"))
    nsheet.save(os.path.join(OUT, f"{name}_n.png"))
    return meta


def _smear(img, pup, sp, yaw, W, H, gy):
    """Pale motion arc along the weapon tip path for the strike frame."""
    pts = []
    for k in range(0, 9):
        t = k / 8
        a = pose_for(sp, "attack", 2, 6)
        b = pose_for(sp, "attack", 3, 6)
        pose = {key: a.get(key, 0) + (b.get(key, 0) - a.get(key, 0)) * t for key in set(a) | set(b)}
        J = pup.joints(pose)
        tip = J["handR"] + J["foreR"] * 18
        pts.append(project(tip, yaw, W / 2, gy))
    pts = pts
    for k in range(len(pts) - 1):
        (x0, y0, _), (x1, y1, _) = pts[k], pts[k + 1]
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for j in range(n):
            x = int(x0 + (x1 - x0) * j / n)
            y = int(y0 + (y1 - y0) * j / n)
            for w in range(-2, 3):
                xx, yy = x, y + w
                if 0 <= xx < W and 0 <= yy < H and img[yy, xx, 3] == 0:
                    a = int(120 + 100 * k / len(pts))
                    img[yy, xx] = (235, 232, 215, a)


def main(names=None):
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {"characters": {}, "props": {}}
    for name in (names or CHARS):
        manifest["characters"][name] = build(name)
        print("rendered", name)
    json.dump(manifest, open(manifest_path, "w"), indent=1)


if __name__ == "__main__":
    import sys
    main(sys.argv[1:] or None)
