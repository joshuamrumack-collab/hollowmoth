"""Cut Nana's ghost poses and portrait out of DorkTeach's sheets.

  python tools/artgen/import_nana.py Art/nana.jpg Art/nana2.jpg

nana.jpg  : framed portrait  -> assets/portrait_nana_framed.png (128) + portrait_nana.png (96)
nana2.jpg : 2x2 pose sheet   -> assets/prop_nana_{idle,cheer,cast,fly}.png (alpha keyed off the dark background)
"""
import sys
import numpy as np
from PIL import Image

OUT = "assets/"


def poses(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    S = a.shape[0] // 2
    bg = np.median(a[:40, :40].reshape(-1, 3), 0)
    for (cx, cy), n in {(0, 0): "idle", (1, 0): "cheer", (0, 1): "cast", (1, 1): "fly"}.items():
        q = a[cy * S:(cy + 1) * S, cx * S:(cx + 1) * S]
        al = np.clip(np.clip(q - bg, 0, None).max(2) / 70.0, 0, 1) ** 0.9
        ys, xs = np.where(al > 0.08)
        y0, y1 = max(0, ys.min() - 8), min(S - 1, ys.max() + 8)
        x0, x1 = max(0, xs.min() - 8), min(S - 1, xs.max() + 8)
        rgb = np.clip((q - bg[None, None] * (1 - al[..., None])) / np.maximum(al[..., None], 1e-3), 0, 255)
        im = Image.fromarray(np.dstack([rgb, al * 255])[y0:y1, x0:x1].astype(np.uint8), "RGBA")
        s = 170 / im.height
        im.resize((round(im.width * s), 170), Image.LANCZOS).save(OUT + "prop_nana_%s.png" % n)


def portrait(path):
    p = Image.open(path).convert("RGB")
    k = p.width / 1000.0
    p.crop((int(55 * k), int(55 * k), int(945 * k), int(945 * k))).resize((128, 128), Image.LANCZOS).save(OUT + "portrait_nana_framed.png")
    p.crop((int(140 * k), int(140 * k), int(860 * k), int(860 * k))).resize((96, 96), Image.LANCZOS).save(OUT + "portrait_nana.png")


if __name__ == "__main__":
    portrait(sys.argv[1] if len(sys.argv) > 1 else "Art/nana.jpg")
    poses(sys.argv[2] if len(sys.argv) > 2 else "Art/nana2.jpg")
    print("nana imported")
