extends Node
## Autoload "Items": Diablo-style loot with Pathfinder 1e properties.
## An item is a Dictionary: {slot, rarity, name, enh, props:{...}}

const RARITY := {
	"normal": Color(0.85, 0.82, 0.75),
	"magic": Color(0.45, 0.6, 1.0),
	"rare": Color(1.0, 0.85, 0.3),
	"unique": Color(0.85, 0.55, 0.2),
}
const WEAPON_NAMES := {"average": "Greataxe", "puck": "Rapier", "brokk": "Longbow", "sael": "Starknife"}
const ARMOR_NAMES := {"average": "Hide Harness", "puck": "Leather Coat", "brokk": "Chain Shirt", "sael": "Moth-silk Robe"}
const TRINKETS := ["Ring", "Amulet", "Charm"]

const WEAPON_PREFIX := {
	"flaming": ["Flaming", "+1d6 fire on hit"],
	"shocking": ["Shocking", "+1d6 lightning on hit"],
	"frost": ["Frost", "hits slow the target"],
	"keen": ["Keen", "doubled threat range"],
	"vicious": ["Vicious", "+2d6 damage, 1d6 to you"],
	"ghost_touch": ["Ghost-touch", "+2 damage to undead"],
}
const WEAPON_SUFFIX := {
	"bear": ["of the Bear", "+1 attack and damage"],
	"leech": ["of the Leech", "heal 1 on hit"],
	"grudge": ["of Grudges", "+2 damage vs wounded foes"],
	"fury": ["of Fury", "more damage the more hurt you are"],
}
const ARMOR_SUFFIX := {
	"fortitude": ["of Fortitude", "+2 Fortitude"],
	"resistance": ["of Resistance", "+1 all saves"],
	"stamina": ["of the Ox", "+15 stamina"],
	"poise": ["of the Mountain", "+20 poise"],
	"spikes": ["of Spikes", "attackers take 1d4"],
}
const TRINKET_SUFFIX := {
	"deflection": ["of Protection", "+1 AC"],
	"swiftness": ["of Swiftness", "+8% move speed"],
	"vigor": ["of Vigor", "+6 max HP"],
	"will": ["of Iron Will", "+2 Will"],
	"fortune": ["of Fortune", "+15% Starlight from kills"],
	"mending": ["of Mending", "draughts heal 50% more"],
}

## Named uniques: fixed properties plus one special power each. Bosses drop their own.
const UNIQUES := {
	"grandmothers_thorn": {"name": "Grandmother's Thorn", "slot": "weapon", "enh": 2, "props": ["keen", "frost"],
		"special": "thorn", "text": "Crits make Nana heal the whole party 4"},
	"bog_kings_due": {"name": "The Bog King's Due", "slot": "armor", "enh": 2, "props": ["poise"],
		"special": "thorns", "text": "Attackers take 1d6, every time"},
	"starless_promise": {"name": "Starless Promise", "slot": "trinket", "enh": 2, "props": ["will", "fortune"],
		"special": "starlit", "text": "Kills drop +25% more Starlight"},
	"better_half": {"name": "Average's Better Half", "slot": "weapon", "enh": 3, "props": ["bear", "fury"],
		"special": "glory", "text": "Every hit fills Glory a little more"},
	"moth_eaten_glory": {"name": "Moth-Eaten Glory", "slot": "armor", "enh": 2, "props": ["stamina"],
		"special": "second_wind", "text": "Once per rest, at low HP: heal 30%"},
	"lost_page": {"name": "Brokk's Lost Page", "slot": "trinket", "enh": 2, "props": ["swiftness"],
		"special": "feather", "text": "Dodging costs half the stamina"},
	"iron_knuckle": {"name": "The Iron Brother's Knuckle", "slot": "weapon", "enh": 3, "props": ["vicious"],
		"special": "thunder", "text": "Crits shake the ground: 2d6 to foes nearby", "boss": "iron_brother"},
	"mourners_veil": {"name": "The Mourner's Veil", "slot": "armor", "enh": 3, "props": ["resistance"],
		"special": "mirror", "text": "15% of blows strike a reflection instead", "boss": "mirror_wraith"},
	"mothers_wing": {"name": "The Mother's Wing", "slot": "trinket", "enh": 3, "props": ["vigor", "mending"],
		"special": "dust", "text": "Dodging leaves a puff of sleeping dust", "boss": "shadow_moth"},
	"ashmaws_ember": {"name": "Ashmaw's Ember", "slot": "weapon", "enh": 4, "props": ["flaming", "keen"],
		"special": "ember", "text": "Hits burn for another 2d6 fire", "boss": "dragon"},
}


## Sigil stones (DorkTeach's sigil sheet): socket them into gear for a permanent power.
## Each one grants an existing property, so socketed sigils stack with affixes.
const SIGILS := {
	"moth": {"name": "Moth Sigil", "prop": "fortune", "text": "+15% Starlight from kills", "col": Color(0.85, 0.9, 1.0)},
	"eye": {"name": "Eye Sigil", "prop": "keen", "text": "doubled threat range", "col": Color(1.0, 0.85, 0.35)},
	"star": {"name": "Star Sigil", "prop": "resistance", "text": "+1 all saves", "col": Color(0.9, 0.9, 1.0)},
	"fire": {"name": "Fire Sigil", "prop": "flaming", "text": "+1d6 fire on hit", "col": Color(1.0, 0.5, 0.25)},
	"skull": {"name": "Skull Sigil", "prop": "leech", "text": "heal 1 on hit", "col": Color(0.75, 0.85, 0.55)},
	"moon": {"name": "Moon Sigil", "prop": "will", "text": "+2 Will", "col": Color(0.8, 0.85, 1.0)},
	"chain": {"name": "Chain Sigil", "prop": "poise", "text": "+20 poise", "col": Color(1.0, 0.45, 0.35)},
	"lightning": {"name": "Storm Sigil", "prop": "shocking", "text": "+1d6 lightning on hit", "col": Color(0.6, 0.7, 1.0)},
	"thorn": {"name": "Thorn Sigil", "prop": "spikes", "text": "attackers take 1d4", "col": Color(0.45, 0.95, 0.45)},
}
const MAX_SOCKETS := 4


func make_sigil(id: String = "") -> Dictionary:
	if id == "":
		id = SIGILS.keys().pick_random()
	return {"slot": "sigil", "rarity": "magic", "enh": 0, "props": {}, "name": "", "sigil": id}


## How many sockets an item has (older saves: worked out from rarity).
func sockets(it: Dictionary) -> int:
	if it.is_empty() or it.get("slot", "") == "sigil":
		return 0
	if it.has("sockets"):
		return int(it["sockets"])
	return {"normal": 1, "magic": 1, "rare": 2, "unique": 2}.get(it.get("rarity", "normal"), 1)


func sigils_of(it: Dictionary) -> Array:
	return it.get("sigils", [])


## Put a sigil into the item's next free socket. Returns false if it is full.
func socket(it: Dictionary, sigil_id: String) -> bool:
	var have: Array = sigils_of(it)
	if have.size() >= sockets(it):
		return false
	it["sockets"] = sockets(it)
	it["sigils"] = have + [sigil_id]
	return true


func has_prop(it: Dictionary, name: String) -> bool:
	if it.get("props", {}).has(name):
		return true
	for sg in sigils_of(it):
		if SIGILS.has(sg) and SIGILS[sg]["prop"] == name:
			return true
	return false


func roll_rarity(luck: float = 0.0) -> String:
	var r := randf() - luck
	if r < 0.04:
		return "unique"
	if r < 0.18:
		return "rare"
	if r < 0.5:
		return "magic"
	return "normal"


## A named unique (by id), as an item dictionary.
func make_unique(id: String) -> Dictionary:
	var u: Dictionary = UNIQUES[id]
	var props := {}
	for k in u["props"]:
		props[k] = true
	props[u["special"]] = true
	return {"slot": u["slot"], "rarity": "unique", "enh": u["enh"] + (Run.act - 1 if not u.has("boss") else 0),
		"props": props, "name": "", "unique_name": u["name"], "unique_id": id, "sockets": 3 if u.has("boss") else 2}


func make(slot: String, luck: float = 0.0) -> Dictionary:
	var rarity := roll_rarity(luck + 0.08 * (Run.act - 1))
	if rarity == "unique":
		# a named piece for this slot that isn't a boss's own
		var ids := UNIQUES.keys().filter(func(k): return UNIQUES[k]["slot"] == slot and not UNIQUES[k].has("boss"))
		if not ids.is_empty():
			return make_unique(ids.pick_random())
	var it := {"slot": slot, "rarity": rarity, "enh": 0, "props": {}, "name": "",
		"sockets": {"normal": randi_range(0, 1), "magic": randi_range(1, 2), "rare": randi_range(2, 3), "unique": 3}[rarity]}
	if slot == "trinket":
		it["base"] = TRINKETS.pick_random()
	var n_props: int = {"normal": 0, "magic": 1, "rare": 2, "unique": 3}[rarity]
	it["enh"] = {"normal": 0, "magic": randi_range(0, 1), "rare": randi_range(1, 2), "unique": randi_range(2, 3)}[rarity]
	if Run.act >= 2:
		it["enh"] += Run.act - 1   # beyond each rift the metal is better
	var pools: Array
	match slot:
		"weapon": pools = [WEAPON_PREFIX, WEAPON_SUFFIX]
		"armor": pools = [ARMOR_SUFFIX]
		_: pools = [TRINKET_SUFFIX]
	var tries := 0
	while it["props"].size() < n_props and tries < 20:
		tries += 1
		var pool: Dictionary = pools.pick_random()
		var key: String = pool.keys().pick_random()
		it["props"][key] = true
	if rarity == "unique":
		it["unique_name"] = ["Grandmother's Thorn", "The Bog King's Due", "Starless Promise", "Average's Better Half", "Moth-Eaten Glory"].pick_random()
	return it


## Ring, Amulet or Charm (older saves: picked from the item's affixes so it never changes).
func trinket_base(it: Dictionary) -> String:
	if it.has("base"):
		return it["base"]
	return TRINKETS[abs(hash(str(it.get("props", {}).keys()) + str(it.get("enh", 0)))) % 3]


func describe(it: Dictionary, hero_id: String) -> String:
	if it.is_empty():
		return "-"
	if it.get("slot", "") == "sigil":
		return SIGILS[it["sigil"]]["name"]
	if it.has("unique_name"):
		return it["unique_name"]
	var base := ""
	match it["slot"]:
		"weapon": base = WEAPON_NAMES[hero_id]
		"armor": base = ARMOR_NAMES[hero_id]
		_: base = trinket_base(it)
	var pre := ""
	var suf := ""
	for k in it["props"]:
		if WEAPON_PREFIX.has(k):
			pre = WEAPON_PREFIX[k][0] + " "
		elif WEAPON_SUFFIX.has(k):
			suf = " " + WEAPON_SUFFIX[k][0]
		elif ARMOR_SUFFIX.has(k):
			suf = " " + ARMOR_SUFFIX[k][0]
		elif TRINKET_SUFFIX.has(k):
			suf = " " + TRINKET_SUFFIX[k][0]
	var enh := ("+%d " % it["enh"]) if it["enh"] > 0 else ""
	return enh + pre + base + suf


func details(it: Dictionary) -> String:
	var parts := []
	if it.get("slot", "") == "sigil":
		return SIGILS[it["sigil"]]["text"] + "  (socket it into gear: R)"
	if it.has("unique_id"):
		parts.append(UNIQUES[it["unique_id"]]["text"])
	if it.get("enh", 0) > 0:
		parts.append("+%d %s" % [it["enh"], "attack/damage" if it["slot"] == "weapon" else ("AC" if it["slot"] == "armor" else "saves")])
	for k in it.get("props", {}):
		if it.has("unique_id") and k == UNIQUES[it["unique_id"]]["special"]:
			continue
		for pool in [WEAPON_PREFIX, WEAPON_SUFFIX, ARMOR_SUFFIX, TRINKET_SUFFIX]:
			if pool.has(k):
				parts.append(pool[k][1])
	for sg in sigils_of(it):
		parts.append("%s: %s" % [SIGILS[sg]["name"], SIGILS[sg]["text"]])
	return ", ".join(parts)


func score(it: Dictionary) -> float:
	if it.is_empty():
		return -1.0
	if it.get("slot", "") == "sigil":
		return 0.0
	return it.get("enh", 0) * 2.0 + it.get("props", {}).size() * 1.5 + sigils_of(it).size() * 1.5 + sockets(it) * 0.2 \
		+ {"normal": 0.0, "magic": 0.5, "rare": 1.0, "unique": 2.0}[it["rarity"]]
