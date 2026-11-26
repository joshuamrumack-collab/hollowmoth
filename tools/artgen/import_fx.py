"""Cut DorkTeach's spell / blood effect sheets (2x2 each) into assets/fx/*.png."""
import os, sys
import numpy as np
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(__file__), "import_concepts.py")).read()
ns = {"__file__": os.path.join(os.path.dirname(__file__), "import_concepts.py")}
exec(src.split("cuts = {i")[0].replace("SRC = sys.argv[1]", "SRC=''").replace("OUT = sys.argv[2]", "OUT=''"), ns)

SHEETS = {
    "b3_16": ["smoke_purple", "smoke_green", "rune_ring", "moon"],
    "b3_17": ["dome", "burst", "moths", "chains"],
    "b3_18": ["blood_splat", "blood_pool", "slash", "crater"],
}
code = open(os.path.join(os.path.dirname(__file__), "import_concepts.py")).read()
quad_src = code[code.index("def quad("):code.index("# hero pose sheets")]
exec(quad_src, ns)
for img, names in SHEETS.items():
    cut = ns["cutout"](os.path.join(SRC, img + ".jpg"))
    for k, name in enumerate(names):
        rgba = ns["quad"](cut, k % 2, k // 2).astype(np.float32)
        # trim the soft background halo: it reads as fog once scaled up over the dark world
        a = rgba[..., 3] / 255.0
        rgba[..., 3] = np.clip((a - 0.3) / 0.7, 0, 1) ** 1.2 * 255
        im = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
        im.thumbnail((256, 256), Image.LANCZOS)
        im.save(os.path.join(OUT, f"{name}.png"))
        print(name, im.size)
