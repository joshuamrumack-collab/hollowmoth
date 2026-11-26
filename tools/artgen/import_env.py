"""Edge and set-dressing props from the free "Undead" top-down tileset (craftpix.net, by Szadi art;
licence in tools/env_src/undead/License.txt). Pixel art, kept crisp at half scale.

  python tools/artgen/import_env.py
"""
import json, os
from PIL import Image

SRC = "tools/env_src/undead/"
PICK = {
    "ud_thorn_0": "Thorn_plant_shadow1_1", "ud_thorn_1": "Thorn_plant_shadow1_2", "ud_thorn_2": "Thorn_plant_shadow1_4",
    "ud_deadtree_0": "Dead_tree_shadow1_1", "ud_deadtree_1": "Dead_tree_shadow1_2",
    "ud_tree_0": "Tree_shadow1_1", "ud_tree_1": "Tree_shadow1_2",
    "ud_rock_0": "Rock_shadow1_1", "ud_rock_1": "Rock_shadow1_2", "ud_rock_2": "Rock_shadow1_3",
    "ud_ruin_0": "Ruin_shadow1_1", "ud_ruin_1": "Ruin_shadow1_2", "ud_ruin_2": "Ruin_shadow1_3",
    "ud_log_0": "Broken_tree_shadow1_1", "ud_stump_0": "Broken_tree_shadow1_4",
    "ud_crystal_0": "Crystal_shadow1_1", "ud_crystal_1": "Crystal_shadow1_2",
    "ud_arm_0": "Dead_arm_shadow1_1", "ud_arm_1": "Dead_arm_shadow1_2", "ud_arm_2": "Dead_arm_shadow1_3", "ud_arm_3": "Dead_arm_shadow1_4",
    "ud_skulls": "Pile_sculls_shadow1", "ud_bush_0": "Plant_shadow1_1", "ud_bush_1": "Plant_shadow1_2",
    "ud_grave_0": "Grave_shadow1_1", "ud_grave_1": "Grave_shadow1_2", "ud_grave_2": "Grave_shadow1_3",
    "ud_grave_3": "Grave_shadow1_4", "ud_grave_4": "Grave_shadow1_5", "ud_grave_5": "Grave_shadow1_6",
    "ud_bones_0": "Bones_shadow1_6", "ud_bones_1": "Bones_shadow1_7", "ud_bones_2": "Bones_shadow1_8", "ud_bones_3": "Bones_shadow1_9",
}
# and the Stone Cemetery pack (craftpix.net): crosses, gravestones, angels
CEM = "tools/env_src/cemetery/"
CEM_PICK = {
    "cem_cross_0": "Cross_Cross_01", "cem_cross_1": "Cross_Cross_02", "cem_cross_2": "Cross_Cross_05", "cem_cross_3": "Cross_Cross_07",
    "cem_cross_4": "Cross_Cross_10", "cem_stone_0": "Grave_Gravestone_02", "cem_stone_1": "Grave_Gravestone_03",
    "cem_stone_2": "Grave_Gravestone_04", "cem_stone_3": "Grave_Gravestone_09", "cem_column": "Colum_Column_01",
    "cem_angel_0": "Big_a_Sculpture_01", "cem_angel_1": "Big_a_Sculpture_07", "cem_angel_s0": "Small_Sculpture_01",
    "cem_angel_s1": "Small_Sculpture_06", "cem_angel_s2": "Small_Sculpture_08",
}
man = json.load(open("assets/manifest.json"))
for name, f in CEM_PICK.items():
    im = Image.open(CEM + f + ".png").convert("RGBA")
    im = im.crop(im.getbbox())
    im.save("assets/prop_%s.png" % name)
    man["props"][name] = {"w": im.width, "h": im.height, "scale": 0.5, "normal": False}
for name, f in PICK.items():
    im = Image.open(SRC + f + ".png").convert("RGBA")
    im = im.crop(im.getbbox())
    im.save("assets/prop_%s.png" % name)
    man["props"][name] = {"w": im.width, "h": im.height, "scale": 0.5, "normal": False}
json.dump(man, open("assets/manifest.json", "w"), indent=1)
print("env props:", len(PICK))
