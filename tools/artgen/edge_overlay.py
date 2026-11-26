"""A see-where-you-can-walk overlay, made from each level's walk mask.

Drawn over the ground and under everyone, unlit: the ground beyond the walkable area sinks into
shadow and a faint pale line traces the edge, so borders read even in the dark.

  python tools/artgen/edge_overlay.py            (all levels)
"""
import json, glob
import numpy as np
from PIL import Image
from scipy import ndimage

S = 0.5            # overlay pixels per world unit


def build(level_path):
    L = json.load(open(level_path))
    if "walkmask" not in L:
        return
    m = np.asarray(Image.open("assets/%s.png" % L["walkmask"]).convert("L")) > 127
    ws = float(L.get("walkmask_scale", 1.0))          # mask pixels per world unit
    k = S / ws
    small = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((max(1, int(m.shape[1] * k)), max(1, int(m.shape[0] * k))), Image.BILINEAR)) > 127
    din = ndimage.distance_transform_edt(small) / S          # world units inside
    dout = ndimage.distance_transform_edt(~small) / S        # world units outside
    a = np.zeros(small.shape, np.float32)
    col = np.zeros(small.shape + (3,), np.float32)
    # shadow beyond the edge, deepening over ~30 units
    shade = np.clip(dout / 30.0, 0, 1) ** 0.7 * 0.7 * (~small)
    a = np.maximum(a, shade)
    # a faint pale lip just inside the edge
    lip = np.clip(1.0 - np.abs(din - 2.0) / 2.5, 0, 1) * small * 0.3
    col[lip > a] = [230, 215, 175]
    a = np.maximum(a, lip)
    rgba = np.dstack([col, a * 255]).astype(np.uint8)
    name = "edge_" + L["walkmask"].replace("walkmask_", "")
    Image.fromarray(rgba, "RGBA").save("assets/%s.png" % name)
    L["edge_overlay"] = name
    L["edge_scale"] = 1.0 / S
    json.dump(L, open(level_path, "w"))
    print(level_path, "->", name, small.shape)


if __name__ == "__main__":
    for p in ["assets/level.json", "assets/level_2.json", "assets/level_3.json"]:
        build(p)
