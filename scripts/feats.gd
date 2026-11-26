extends RefCounted
## Feats: each level-up offers three, Pathfinder style. Companions pick their own.
## Stat feats are folded into Hero.recalc(); the rest are checked where they act (has_feat()).

const ALL := {
	# --- anyone
	"toughness": {"name": "Toughness", "desc": "+3 HP, and +1 HP every level", "who": "all"},
	"great_fortitude": {"name": "Great Fortitude", "desc": "+2 Fortitude saves", "who": "all"},
	"iron_will": {"name": "Iron Will", "desc": "+2 Will saves", "who": "all"},
	"lightning_reflexes": {"name": "Lightning Reflexes", "desc": "+2 Reflex saves", "who": "all"},
	"dodge": {"name": "Dodge", "desc": "+1 AC", "who": "all"},
	"weapon_focus": {"name": "Weapon Focus", "desc": "+1 to hit", "who": "all"},
	"power_attack": {"name": "Power Attack", "desc": "+3 damage, -1 to hit", "who": "all"},
	"endurance": {"name": "Endurance", "desc": "+20 stamina", "who": "all"},
	"fleet": {"name": "Fleet", "desc": "Move 10% faster", "who": "all"},
	"improved_critical": {"name": "Improved Critical", "desc": "Double your critical threat range", "who": "all"},
	"diehard": {"name": "Diehard", "desc": "Once per rest, a killing blow leaves you at 1 HP", "who": "all"},
	"steadfast": {"name": "Steadfast", "desc": "+25 poise: harder to stagger", "who": "all"},
	# --- Average
	"extra_rage": {"name": "Extra Rage", "desc": "Rage lasts longer and comes back sooner", "who": "average"},
	"glory_hound": {"name": "Glory Hound", "desc": "Double Glory from kills. LOOK AT HIM.", "who": "average"},
	"unstoppable": {"name": "Unstoppable", "desc": "While raging: +40 poise, +2 AC", "who": "average"},
	# --- Puck
	"weapon_finesse": {"name": "Weapon Finesse", "desc": "+2 to hit with the rapier", "who": "puck"},
	"dreamweaver": {"name": "Dreamweaver", "desc": "Herb smoke spreads 30% wider, lingers longer", "who": "puck"},
	"nanas_favourite": {"name": "Nana's Favourite", "desc": "Sneak attacks make Nana heal you a little", "who": "puck"},
	# --- Brokk
	"arcane_strike": {"name": "Arcane Strike", "desc": "Spell arrows deal +1d6", "who": "brokk"},
	"point_blank": {"name": "Point-Blank Shot", "desc": "+2 damage against foes close by", "who": "brokk"},
	"long_memory": {"name": "Long Memory", "desc": "Grudges hit even harder (+3 per die)", "who": "brokk"},
	# --- Eowilas
	"selective_channel": {"name": "Selective Channeling", "desc": "Channel heals 50% more", "who": "sael"},
	"extra_channel": {"name": "Extra Channel", "desc": "+2 spell slots per rest", "who": "sael"},
	"butterfly_grace": {"name": "Butterfly's Grace", "desc": "+1 AC and +1 to all saves", "who": "sael"},
}


static func info(id: String) -> Dictionary:
	return ALL.get(id, {"name": id, "desc": "", "who": "all"})


## Three feats the hero doesn't have yet; one is always their own if any are left.
static func offer(hero_id: String, owned: Array, n := 3) -> Array:
	var own := []
	var general := []
	for id in ALL:
		if id in owned:
			continue
		if ALL[id]["who"] == hero_id:
			own.append(id)
		elif ALL[id]["who"] == "all":
			general.append(id)
	own.shuffle()
	general.shuffle()
	var out := []
	if not own.is_empty():
		out.append(own.pop_back())
	var pool := own + general
	pool.shuffle()
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_back())
	return out


## Companions choose for themselves: their own feats first, then whatever suits them.
static func auto_pick(hero_id: String, owned: Array) -> String:
	var o := offer(hero_id, owned, 3)
	if o.is_empty():
		return ""
	for id in o:
		if ALL[id]["who"] == hero_id:
			return id
	var pref := {"average": ["power_attack", "toughness", "steadfast"], "puck": ["dodge", "weapon_focus", "lightning_reflexes"],
		"brokk": ["weapon_focus", "improved_critical", "toughness"], "sael": ["toughness", "iron_will", "dodge"]}
	for id in pref.get(hero_id, []):
		if id in o:
			return id
	return o[0]
