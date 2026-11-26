class_name Hero
extends Combatant
## The four heroes. One is controlled by the player; the rest run party AI.
## Kits: Attack / Special / Cast / Dash / Parry + three abilities (1-3).

var hero_id := "average"
var controlled := false
var combo := 0
var cds := {}                 # ability name -> cooldown seconds
var think_t := 0.0
var ai_target: Combatant = null
var dodge_cd := 0.0
var bark_cd := 0.0

# Average
var glory := 0.0
# Puck
var herbs := 6
var herb_index := 0
const HERBS := ["Dreamleaf", "Gigglecap", "Sunthistle"]
var nana_used := false
var praise_cd := 0.0
# Brokk
var arcane_pool := 6
var spell_index := 0
const SPELLS := ["Shock", "Fire", "Frost"]
var grudges := {}
var many_shot := 0
# Eowilas
var slots := 4
var nana_sprite: Sprite2D = null
var nana_pose := "idle"           # idle, cheer (praise), cast (steps in / heals), fly (Puck on the move)
var nana_pose_t := 0.0
var moth_sprite: Sprite2D = null
var dome_sprite: Sprite2D = null
# Progression and gear
var level := 1
var feats: Array = []           # feat ids picked on level-up (see feats.gd)
var gear := {"weapon": {}, "armor": {}, "trinket": {}}
var base := {}
const Feats = preload("res://scripts/feats.gd")
var diehard_used := false
const Brains = preload("res://scripts/ai/brains.gd")
var brain: BeehaveTree = null   # personality (scripts/ai/brains.gd); reflexes stay in _ai()
var since_kill := 99.0
var bt_stats := {}
var claimed: Combatant = null   # the big one Average has called dibs on
var emote_kind := ""
var emote_t := 0.0
var second_wind_used := false
var finesse_nana_cd := 0.0
const HIT_DIE := {"average": 7, "puck": 5, "brokk": 6, "sael": 5}
const FULL_BAB := ["average", "brokk"]


static func level_cost(lvl: int) -> int:
	return int(350.0 * pow(lvl, 1.35))


func has_feat(id: String) -> bool:
	return id in feats


func add_feat(id: String) -> void:
	if id == "" or id in feats:
		return
	feats.append(id)
	recalc()


func prop(name: String) -> bool:
	for slot in gear:
		if Items.has_prop(gear[slot], name):
			return true
	return false


func enh(slot: String) -> int:
	return int(gear[slot].get("enh", 0))


## Rebuilds derived stats from base + level + gear.
func recalc() -> void:
	var l := level - 1
	var old_max := max_hp
	max_hp = base["hp"] + HIT_DIE[hero_id] * l + (6 if prop("vigor") else 0) + ((3 + level) if has_feat("toughness") else 0)
	bab = base["bab"] + (l if hero_id in FULL_BAB else int(l * 0.75))
	var fac := (1 if has_feat("dodge") else 0) + (1 if has_feat("butterfly_grace") else 0) + (2 if has_feat("unstoppable") and has("raging") else 0)
	ac = base["ac"] + enh("armor") + (1 if prop("deflection") else 0) + int(l / 3) + fac
	flat_ac = base["flat"] + enh("armor") + (1 if prop("deflection") else 0)
	var sv: Dictionary = base["saves"]
	var res := (1 if prop("resistance") else 0) + enh("trinket") + int(l / 2) + (1 if has_feat("butterfly_grace") else 0)
	saves = {"fort": sv["fort"] + res + (2 if prop("fortitude") else 0) + (2 if has_feat("great_fortitude") else 0),
		"ref": sv["ref"] + res + (2 if has_feat("lightning_reflexes") else 0),
		"will": sv["will"] + res + (2 if prop("will") else 0) + (2 if has_feat("iron_will") else 0)}
	max_stamina = base["stamina"] + (15.0 if prop("stamina") else 0.0) + l * 3.0 + (20.0 if has_feat("endurance") else 0.0)
	poise_max = base["poise"] + (20.0 if prop("poise") else 0.0) + (25.0 if has_feat("steadfast") else 0.0)
	if has("raging"):
		poise_max += 25.0 + (40.0 if has_feat("unstoppable") else 0.0)
	speed = base["speed"] * (1.08 if prop("swiftness") else 1.0) * (1.1 if has_feat("fleet") else 1.0)
	if max_hp > old_max and not is_dead():
		hp += max_hp - old_max
	hp = min(hp, max_hp)


func level_up() -> void:
	level += 1
	if main != null and self != main.leader:
		add_feat(Feats.auto_pick(hero_id, feats))
	recalc()
	hp = max_hp
	if self != main.leader:
		return
	main.float_text(global_position + Vector2(0, -sprite_h - 6), "LEVEL %d" % level, Color(1.0, 0.9, 0.55), 1.6)


func equip(it: Dictionary) -> Dictionary:
	var old: Dictionary = gear[it["slot"]]
	gear[it["slot"]] = it
	recalc()
	return old


func _ready() -> void:
	brain = Brains.build(self)
	add_child(brain)


func setup(id: String) -> void:
	hero_id = id
	team = "hero"
	sprite_id = id
	match id:
		"average":
			display_name = "Average"
			max_hp = 45; ac = 14; flat_ac = 13; bab = 3
			saves = {"fort": 6, "ref": 2, "will": 1}
			speed = 78.0; radius = 8.0; poise_max = 45.0
			max_stamina = 85.0
			color = Color(0.55, 0.32, 0.24)
		"puck":
			display_name = "Puck"
			max_hp = 24; ac = 16; flat_ac = 12; bab = 2
			saves = {"fort": 1, "ref": 7, "will": 4}
			speed = 86.0; radius = 6.0; poise_max = 20.0
			max_stamina = 55.0
			color = Color(0.28, 0.36, 0.28)
		"brokk":
			display_name = "Brokk"
			max_hp = 28; ac = 16; flat_ac = 13; bab = 2
			saves = {"fort": 5, "ref": 4, "will": 3}
			speed = 70.0; radius = 6.5; poise_max = 30.0
			max_stamina = 65.0
			color = Color(0.45, 0.36, 0.26)
		"sael":
			display_name = "Eowilas"
			max_hp = 22; ac = 17; flat_ac = 15; bab = 2
			saves = {"fort": 4, "ref": 2, "will": 6}
			speed = 76.0; radius = 6.0; poise_max = 22.0
			max_stamina = 50.0
			color = Color(0.14, 0.14, 0.17)
	base = {"hp": max_hp, "ac": ac, "flat": flat_ac, "bab": bab, "saves": saves.duplicate(), "stamina": max_stamina,
		"poise": poise_max, "speed": speed}
	setup_common()
	if id == "puck":
		nana_sprite = Sprite2D.new()
		nana_sprite.texture = Art.prop("nana_idle") if Art.prop("nana_idle") != null else Art.prop("nana")
		nana_sprite.scale = Vector2(0.16, 0.16)
		nana_sprite.modulate = Color(1, 1, 1, 0.75)
		# a ghost glows on her own: the night lighting doesn't darken her
		var nm := CanvasItemMaterial.new()
		nm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		nana_sprite.material = nm
		add_child(nana_sprite)
	if id == "sael":
		moth_sprite = Sprite2D.new()
		moth_sprite.texture = Art.prop("moth_0")
		moth_sprite.scale = Vector2(0.15, 0.15)
		add_child(moth_sprite)
	if Art.fx("dome") != null:
		dome_sprite = Sprite2D.new()
		dome_sprite.texture = Art.fx("dome")
		dome_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		dome_sprite.scale = Vector2.ONE * 52.0 / Art.fx("dome").get_size().x
		dome_sprite.position = Vector2(0, -12)
		dome_sprite.visible = false
		add_child(dome_sprite)


func rest() -> void:
	if is_dead():
		state = State.IDLE
		z_index = 0
		collision_layer = 1
		collision_mask = 1
	recalc()
	hp = max_hp
	stamina = max_stamina
	conditions.clear()
	herbs = 6
	arcane_pool = 6
	slots = 4 + (2 if has_feat("extra_channel") else 0)
	diehard_used = false
	second_wind_used = false
	nana_used = false
	cds.clear()


func cd(name: String) -> float:
	return cds.get(name, 0.0)


func _tick_cds(delta: float) -> void:
	for k in cds.keys():
		cds[k] = max(0.0, cds[k] - delta)
	dodge_cd -= delta
	praise_cd -= delta
	since_kill += delta
	emote_t -= delta
	if emote_t <= 0.0 or velocity.length() > 10.0 or state != State.IDLE:
		emote_kind = ""
	finesse_nana_cd -= delta
	bark_cd -= delta


# =====================================================================
# Kits
# =====================================================================

func atk_bonus() -> int:
	var g := enh("weapon") + (1 if prop("bear") else 0) + (1 if has_feat("weapon_focus") else 0) - (1 if has_feat("power_attack") else 0) + (2 if has_feat("weapon_finesse") else 0)
	match hero_id:
		"average": return bab + 4 + g + (2 if has("raging") else 0)
		"puck": return bab + 4 + g
		"brokk": return bab + 3 + g + (4 if has("stand") else 0)
		"sael": return bab - 1 + g
	return bab + g


func basic_attack(i: int) -> Dictionary:
	match hero_id:
		"average":
			var heavy := i == 2
			return {
				"name": "greataxe", "windup": [0.26, 0.22, 0.34][i], "active": 0.08, "recovery": 0.34,
				"shape": "arc", "reach": 22.0, "arc": 110.0, "stamina": 16.0,
				"poise_dmg": 30.0 if heavy else 16.0, "heavy": heavy, "knockback": 70.0 if heavy else 35.0,
				"lunge": 40.0, "combo": i,
				"attack": {"name": "greataxe", "bonus": atk_bonus(), "dice_n": 1, "dice_s": 12,
					"dmg_bonus": 4 + (2 if heavy else 0) + (2 if has("raging") else 0), "threat": 20, "mult": 3},
			}
		"puck":
			return {
				"name": "rapier", "windup": [0.14, 0.12, 0.18][i], "active": 0.07, "recovery": 0.2,
				"shape": "arc", "reach": 20.0, "arc": 60.0, "stamina": 9.0, "poise_dmg": 8.0,
				"lunge": 50.0, "combo": i,
				"attack": {"name": "rapier", "bonus": atk_bonus(), "dice_n": 1, "dice_s": 6,
					"dmg_bonus": 4, "threat": 18, "mult": 2},
			}
		"brokk":
			var w := 0.3 * (0.6 if has("stand") else 1.0)
			var a := {
				"name": "arrow", "windup": w, "active": 0.04, "recovery": 0.22, "stamina": 10.0,
				"poise_dmg": 10.0, "combo": 0,
				"attack": {"name": "arrow", "bonus": atk_bonus(), "dice_n": 1, "dice_s": 8, "dmg_bonus": 1,
					"threat": 20, "mult": 3},
			}
			a["custom"] = func() -> void: _fire_arrows(a, Color(0.75, 0.7, 0.6), false)
			return a
		"sael":
			return {
				"name": "starknife", "windup": 0.3, "active": 0.07, "recovery": 0.35,
				"shape": "arc", "reach": 18.0, "arc": 70.0, "stamina": 12.0, "poise_dmg": 5.0,
				"lunge": 20.0, "combo": i,
				"attack": {"name": "starknife", "bonus": atk_bonus(), "dice_n": 1, "dice_s": 4,
					"dmg_bonus": -1, "threat": 20, "mult": 3},
			}
	return {}


func max_combo() -> int:
	match hero_id:
		"average", "puck": return 3
		"sael": return 2
	return 1


func special() -> Dictionary:
	match hero_id:
		"average":
			return {
				"name": "overhead cleave", "windup": 0.6, "active": 0.1, "recovery": 0.55,
				"shape": "arc", "reach": 26.0, "arc": 60.0, "stamina": 30.0, "poise_dmg": 60.0,
				"heavy": true, "knockback": 110.0, "lunge": 30.0,
				"attack": {"name": "overhead cleave", "bonus": atk_bonus() - 1, "dice_n": 2, "dice_s": 12,
					"dmg_bonus": 7 + (2 if has("raging") else 0), "threat": 20, "mult": 3},
			}
		"puck":
			return {
				"name": "lunge", "windup": 0.2, "active": 0.16, "recovery": 0.35,
				"shape": "arc", "reach": 22.0, "arc": 50.0, "stamina": 22.0, "poise_dmg": 22.0,
				"lunge": 260.0,
				"attack": {"name": "lunge", "bonus": atk_bonus() + 2, "dice_n": 2, "dice_s": 6,
					"dmg_bonus": 4, "threat": 18, "mult": 2},
			}
		"brokk":
			var a := {
				"name": "power shot", "windup": 0.75 * (0.6 if has("stand") else 1.0), "active": 0.05,
				"recovery": 0.35, "stamina": 24.0, "poise_dmg": 40.0, "pierce": true, "heavy": true,
				"knockback": 80.0,
				"attack": {"name": "power shot", "bonus": atk_bonus(), "dice_n": 2, "dice_s": 8,
					"dmg_bonus": 4, "threat": 19, "mult": 3},
			}
			a["custom"] = func() -> void: _fire_arrows(a, Color(0.95, 0.9, 0.7), true)
			return a
		"sael":
			var a := {
				"name": "starknife throw", "windup": 0.3, "active": 0.04, "recovery": 0.3, "stamina": 14.0,
				"poise_dmg": 6.0, "boomerang": true,
				"attack": {"name": "starknife throw", "bonus": bab + 2, "dice_n": 1, "dice_s": 4,
					"dmg_bonus": 0, "threat": 20, "mult": 3},
			}
			a["custom"] = func() -> void:
				main.spawn_projectile(self, global_position + Vector2(0, -6), aim, 200.0, a, Color(0.8, 0.8, 0.9))
			return a
	return {}


func cast() -> Dictionary:
	match hero_id:
		"average":
			if cd("slam") > 0.0:
				return {}
			var a := {
				"name": "ground slam", "windup": 0.5, "active": 0.1, "recovery": 0.5, "stamina": 25.0,
				"shape": "circle", "radius": 38.0, "heavy": true, "poise_dmg": 35.0, "knockback": 90.0,
				"attack": {"name": "ground slam", "bonus": atk_bonus(), "dice_n": 2, "dice_s": 6,
					"dmg_bonus": 4, "threat": 20, "mult": 2},
			}
			a["custom"] = func() -> void:
				cds["slam"] = 7.0
				a["_point"] = global_position
				for t in main.targets_in_area(self, a):
					strike(t, a)
					if not t.is_dead() and not Rules.save(t, "ref", 15, "Ground Slam"):
						t.add_condition("prone", 1.0)
						t.interrupt(0.0)
				main.shake(5.0)
				main.ring(global_position, 38.0, Color(0.6, 0.45, 0.3))
				Sfx.play("slam", global_position); main.fx_sprite("crater", global_position, 70.0, 1.6, {"ground": true, "grow": 0.1, "hold": 0.6, "tint": Color(1, 0.75, 0.6)})
			return a
		"puck":
			if herbs <= 0:
				main.float_text(global_position, "out of herbs", Color(0.6, 0.6, 0.6))
				return {}
			var point := global_position + aim * 70.0
			if not controlled and ai_target != null:
				point = ai_target.global_position
			var herb: String = HERBS[herb_index]
			var a := {"name": "burn " + herb, "windup": 0.25, "active": 0.05, "recovery": 0.25, "stamina": 6.0, "is_attack": false}
			a["custom"] = func() -> void:
				herbs -= 1
				var dc := 15 if has("haze") else 14
				main.spawn_cloud(self, point, 28.0 * (1.3 if has_feat("dreamweaver") else 1.0), 4.0 * (1.4 if has_feat("dreamweaver") else 1.0), herb, dc)
				main.float_text(global_position + Vector2(0, -20), "*puff* " + herb, Color(0.7, 0.9, 0.6))
			return a
		"brokk":
			if arcane_pool <= 0:
				main.float_text(global_position, "arcane pool empty", Color(0.6, 0.6, 0.6))
				return {}
			var spell: String = SPELLS[spell_index]
			var col: Color = {"Shock": Color(0.6, 0.8, 1.0), "Fire": Color(1.0, 0.5, 0.15), "Frost": Color(0.7, 0.95, 1.0)}[spell]
			var a := {
				"name": spell + " arrow", "windup": 0.35 * (0.6 if has("stand") else 1.0), "active": 0.04,
				"recovery": 0.3, "stamina": 12.0, "poise_dmg": 20.0, "spell": spell,
				"attack": {"name": spell + " arrow", "spell": spell, "bonus": atk_bonus(), "dice_n": 1, "dice_s": 8, "dmg_bonus": 1,
					"threat": 20, "mult": 3, "extra_n": 2 if spell == "Fire" else 1, "extra_s": 6},
			}
			a["custom"] = func() -> void:
				arcane_pool -= 1
				_fire_arrows(a, col, false)
			return a
		"sael":
			if slots <= 0:
				main.float_text(global_position, "no spell slots", Color(0.6, 0.6, 0.6))
				return {}
			var a := {"name": "channel energy", "windup": 0.7, "active": 0.05, "recovery": 0.4, "stamina": 10.0, "is_attack": false}
			a["custom"] = func() -> void:
				slots -= 1
				var amt := Rules.roll(2, 6, 2 + level)
				if has_feat("selective_channel"):
					amt = int(amt * 1.5)
				var thanked := false
				for h in main.heroes:
					if not h.is_dead() and h.global_position.distance_to(global_position) < 60.0:
						if h != self and h.hp < h.max_hp * 0.5 and not thanked and randf() < 0.4:
							thanked = true
							main.banter.hero_line("healed", h.hero_id)
						h.heal(amt)
				main.ring(global_position, 60.0, Color(0.85, 0.85, 1.0))
				Sfx.play("heal", global_position); main.fx_sprite("moths", global_position + Vector2(0, -14), 90.0, 1.2, {"spin": 1.2, "grow": 0.4}); main.fx_sprite("burst", global_position + Vector2(0, -12), 60.0, 0.6)
				Rules.logged.emit("Eowilas channels positive energy: party heals %d" % amt)
			return a
	return {}


func ability(n: int) -> void:
	match hero_id:
		"average":
			if n == 1 and cd("rage") <= 0.0:
				add_condition("raging", 16.0 if has_feat("extra_rage") else 12.0)
				cds["rage"] = 20.0 if has_feat("extra_rage") else 30.0
				recalc()
				poise = poise_max
				bark("RAAAGH!")
			elif n == 2:
				if glory >= 100.0:
					glory = 0.0
					add_condition("taunting", 6.0)
					bark(["LOOK AT ME!", "WITNESS AVERAGE!", "NOT SO AVERAGE NOW!"].pick_random())
					main.shake(4.0)
				else:
					main.float_text(global_position, "glory %d%%" % int(glory), Color(0.8, 0.7, 0.3))
		"puck":
			if n == 1:
				herb_index = (herb_index + 1) % HERBS.size()
				main.float_text(global_position + Vector2(0, -20), HERBS[herb_index], Color(0.7, 0.9, 0.6))
			elif n == 2 and herbs > 0 and cd("share") <= 0.0:
				herbs -= 1
				cds["share"] = 4.0
				var herb: String = HERBS[herb_index]
				for h in main.heroes:
					if not h.is_dead() and h.global_position.distance_to(global_position) < 50.0:
						match herb:
							"Dreamleaf":
								h.add_condition("dreamleaf_share", 15.0)
								h.heal(Rules.roll(1, 6))
							"Gigglecap":
								h.add_condition("gigglecap", 12.0)
							"Sunthistle":
								h.add_condition("sunthistle", 10.0)
				bark("Pass it around, friends.")
				main.ring(global_position, 50.0, Color(0.6, 0.9, 0.5))
				main.fx_sprite("smoke_purple" if HERBS[herb_index] == "Dreamleaf" else "smoke_green", global_position + Vector2(0, -10), 60.0, 1.4, {"grow": 0.5, "spin": 0.4})
			elif n == 3 and cd("haze") <= 0.0:
				add_condition("haze", 12.0)
				cds["haze"] = 30.0
				bark("Ohhh... the walls are breathing.")
		"brokk":
			if n == 1:
				spell_index = (spell_index + 1) % SPELLS.size()
				main.float_text(global_position + Vector2(0, -20), SPELLS[spell_index] + " arrow", Color(0.7, 0.8, 1.0))
			elif n == 2 and cd("stand") <= 0.0:
				add_condition("stand", 6.0)
				cds["stand"] = 18.0
				bark("Dwarves don't move. Mountains move around us.")
			elif n == 3 and cd("many") <= 0.0:
				many_shot = 3
				cds["many"] = 12.0
				main.float_text(global_position + Vector2(0, -20), "Many Shot", Color(0.9, 0.8, 0.5))
		"sael":
			if n == 1 and cd("silence") <= 0.0:
				var point := global_position + aim * 60.0
				if not controlled and ai_target != null:
					point = ai_target.global_position
				cds["silence"] = 12.0
				main.spawn_cloud(self, point, 45.0, 7.0, "Silence", 0)
			elif n == 2 and cd("chains") <= 0.0:
				cds["chains"] = 10.0
				for h in main.heroes:
					if not h.is_dead() and h.global_position.distance_to(global_position) < 60.0:
						for c in ["asleep", "confused", "staggered", "prone", "slowed", "nauseated", "parried"]:
							h.conditions.erase(c)
				main.ring(global_position, 60.0, Color(0.9, 0.9, 1.0))
				Sfx.play("cast", global_position); main.fx_sprite("chains", global_position + Vector2(0, -14), 60.0, 0.9, {"grow": 0.5})
				main.float_text(global_position + Vector2(0, -20), "(signs) Be free.", Color(0.85, 0.85, 1.0))
			elif n == 3 and slots > 0:
				var fallen: Hero = main.nearest_fallen(global_position, 70.0)
				if fallen == null:
					main.float_text(global_position, "no fallen ally near", Color(0.6, 0.6, 0.6))
					return
				var a := {"name": "breath of life", "windup": 1.0, "active": 0.05, "recovery": 0.4, "stamina": 10.0, "is_attack": false}
				a["custom"] = func() -> void:
					slots -= 1
					fallen.state = State.IDLE
					fallen.z_index = 0
					fallen.collision_layer = 1
					fallen.collision_mask = 1
					fallen.hp = max(1, fallen.max_hp / 4)
					main.float_text(fallen.global_position, "breath of life", Color(0.9, 0.9, 1.0))
					main.ring(fallen.global_position, 20.0, Color(1, 1, 1))
					Sfx.play("heal", fallen.global_position); main.fx_sprite("burst", fallen.global_position + Vector2(0, -8), 56.0, 0.9)
					main.banter.hero_line("revived", fallen.hero_id)
				start_action(a)


func _fire_arrows(a: Dictionary, col: Color, pierce: bool) -> void:
	var dirs := [aim]
	if many_shot > 0:
		many_shot -= 1
		dirs = [aim.rotated(-0.12), aim.rotated(0.12)]
	for dir in dirs:
		var p: Node = main.spawn_projectile(self, global_position + Vector2(0, -7), dir, 320.0, a, col)
		p.pierce = pierce


# =====================================================================
# Combat hooks
# =====================================================================

func _modify_attack(t: Combatant, atk: Dictionary, sneaky: bool) -> void:
	var l := level - 1
	atk["dmg_bonus"] = atk.get("dmg_bonus", 0) + enh("weapon") + (1 if prop("bear") else 0) + int(l / 2)
	if has_feat("power_attack"):
		atk["dmg_bonus"] = atk["dmg_bonus"] + 3
	if has_feat("point_blank") and t.global_position.distance_to(global_position) < 90.0:
		atk["dmg_bonus"] = atk["dmg_bonus"] + 2
	if has_feat("arcane_strike") and atk.has("spell"):
		atk["extra_n"] = atk.get("extra_n", 0) + 1
		atk["extra_s"] = 6
	if prop("keen") or has_feat("improved_critical"):
		atk["threat"] = 21 - 2 * (21 - int(atk.get("threat", 20)))
	if prop("flaming") or prop("shocking"):
		atk["extra_n"] = atk.get("extra_n", 0) + (1 if prop("flaming") else 0) + (1 if prop("shocking") else 0)
		atk["extra_s"] = 6
	if prop("ember"):
		atk["extra_n"] = atk.get("extra_n", 0) + 2
		atk["extra_s"] = 6
	if prop("fury"):
		atk["dmg_bonus"] = atk["dmg_bonus"] + int((1.0 - float(hp) / max_hp) * 8.0)
	if prop("vicious"):
		atk["dmg_bonus"] = atk["dmg_bonus"] + Rules.roll(2, 6)
		hp = max(1, hp - Rules.roll(1, 6))
	if prop("grudge") and t.hp < t.max_hp / 2:
		atk["dmg_bonus"] = atk["dmg_bonus"] + 2
	if has("taunting"):
		atk["dmg_bonus"] = atk.get("dmg_bonus", 0) * 2 + 4
	if hero_id == "puck" and sneaky:
		atk["extra_n"] = atk.get("extra_n", 0) + 2 + int((level - 1) / 2)
		atk["extra_s"] = 6
		atk["name"] = str(atk.get("name", "")) + " +sneak"
		if has_feat("nanas_favourite") and finesse_nana_cd <= 0.0 and not nana_used:
			finesse_nana_cd = 6.0
			heal(max(2, int(max_hp * 0.08)))
			nana_act("cast", 1.2)
			main.float_text(global_position + Vector2(0, -sprite_h - 12), "Nana: there you go, dear", Color(0.75, 0.9, 1.0), 1.2)
	if hero_id == "brokk" and t is Enemy and grudges.has(t.kind):
		atk["dmg_bonus"] = atk.get("dmg_bonus", 0) + (3 if has_feat("long_memory") else 2) * int(atk.get("dice_n", 1))
		atk["name"] = str(atk.get("name", "")) + " +GRUDGE"


func _on_hit_landed(t: Combatant, res: Dictionary) -> void:
	main.note_leader_target(self, t)
	if prop("frost") and not t.is_dead():
		t.add_condition("slowed", 2.0)
	if prop("glory") and hero_id == "average":
		glory = min(100.0, glory + 3.0)
	if res["result"] == "crit":
		if randf() < (0.5 if hero_id == "average" else 0.25):
			main.banter.hero_line("crit", hero_id)
		if prop("thorn"):
			for h in main.heroes:
				if not h.is_dead():
					h.heal(4)
			if hero_id == "puck":
				nana_act("cast", 1.2)
			main.float_text(global_position + Vector2(0, -sprite_h - 12), "Nana: good thrust, dear!", Color(0.75, 0.9, 1.0), 1.2)
		if prop("thunder"):
			Sfx.play("slam", t.global_position, -2.0)
			main.ring(t.global_position, 34.0, Color(0.9, 0.8, 0.5))
			for e in main.enemies:
				if e != t and not e.is_dead() and e.global_position.distance_to(t.global_position) < 34.0:
					e.take_hit(self, Rules.roll(2, 6), 20.0, "hit", (e.global_position - t.global_position).normalized() * 80.0)
	if prop("leech") and hp < max_hp:
		hp += 1
	if hero_id == "average" and main.watched(self):
		glory = min(100.0, glory + (6.0 if res["result"] != "graze" else 2.0))
	if hero_id == "puck" and str(res.get("result")) != "graze" and t.is_flat_footed():
		nana_praise()
	if action.get("spell", "") != "" and not t.is_dead():
		_spell_effect(t, str(action["spell"]))


## Called by projectiles too (they carry the action dict).
func on_projectile_hit(t: Combatant, a: Dictionary) -> void:
	if a.get("spell", "") != "" and not t.is_dead():
		_spell_effect(t, str(a["spell"]))
	main.note_leader_target(self, t)


func _spell_effect(t: Combatant, spell: String) -> void:
	match spell:
		"Shock":
			var other: Combatant = main.nearest_enemy_except(t.global_position, t, 55.0)
			if other != null:
				var dmg := Rules.roll(1, 6)
				main.zap(t.global_position, other.global_position)
				other.take_hit(self, dmg, 8.0, "hit")
		"Fire":
			for e in main.enemies:
				if e != t and not e.is_dead() and e.global_position.distance_to(t.global_position) < 18.0:
					e.take_hit(self, Rules.roll(1, 6), 6.0, "hit")
			main.ring(t.global_position, 18.0, Color(1.0, 0.5, 0.1))
		"Frost":
			t.add_condition("slowed", 3.0)


## Little in-character moments while the party waits (see banter.gd).
func emote(kind: String, dur: float) -> void:
	emote_kind = kind
	emote_t = dur
	match kind:
		"pray":
			main.fx_sprite("moths", global_position + Vector2(0, -16), 34.0, dur, {"spin": 0.4, "grow": 0.2, "hold": 0.5})
		"pipe":
			main.fx_sprite("smoke_purple", global_position + Vector2(6, -22), 18.0, dur, {"grow": 1.2, "hold": 0.2, "tint": Color(0.8, 0.8, 0.85)})
		"flex":
			glory = min(100.0, glory + 2.0)


func _cheat_death() -> bool:
	if has_feat("diehard") and not diehard_used:
		diehard_used = true
		hp = 1
		main.float_text(global_position + Vector2(0, -sprite_h - 12), "DIEHARD", Color(1.0, 0.85, 0.4), 1.4)
		return true
	return false


## Nana strikes a pose for a moment (her ghost floats beside Puck).
func nana_act(pose: String, t: float) -> void:
	nana_pose = pose
	nana_pose_t = t


func nana_praise() -> void:
	if praise_cd > 0.0:
		return
	praise_cd = 5.0
	for h in main.heroes:
		if not h.is_dead():
			h.temp_hp = min(6, h.temp_hp + 2)
	nana_act("cheer", 1.6)
	main.float_text(global_position + Vector2(0, -26), "Nana: " + ["That's my boy!", "Wonderful, dear!", "So clever!"].pick_random(), Color(0.75, 0.9, 1.0))


func _after_hit(attacker: Combatant, _amount: int) -> void:
	if attacker != null and attacker != self and not attacker.is_dead() and attacker.team != team and (prop("thorns") or prop("spikes")):
		attacker.take_hit(self, Rules.roll(1, 6 if prop("thorns") else 4), 0.0, "hit")
	if prop("second_wind") and not second_wind_used and hp > 0 and hp < max_hp * 0.25:
		second_wind_used = true
		heal(int(max_hp * 0.3))
		main.float_text(global_position + Vector2(0, -sprite_h - 12), "second wind", Color(0.6, 1.0, 0.7), 1.2)
	if hero_id == "brokk" and attacker is Enemy and not grudges.has(attacker.kind):
		grudges[attacker.kind] = true
		main.float_text(global_position + Vector2(0, -26), "GRUDGE: " + attacker.display_name, Color(1.0, 0.6, 0.3))
		bark(["Written down, you festering bog-rat.", "That goes in the book.", "Your mother was a puddle."].pick_random())
	if hero_id == "puck" and not nana_used and hp > 0 and hp < max_hp * 0.2:
		nana_used = true
		add_condition("ward", 6.0)
		nana_act("cast", 2.5)
		main.float_text(global_position + Vector2(0, -30), "NANA STEPS IN: \"Not my grandson!\"", Color(0.7, 0.85, 1.0))
		for e in main.enemies:
			if not e.is_dead() and e.global_position.distance_to(global_position) < 55.0:
				if not Rules.save(e, "will", 16, "Nana's lullaby"):
					e.add_condition("asleep", 5.0)
					e.interrupt(0.0)
		main.ring(global_position, 55.0, Color(0.6, 0.7, 1.0))
		Sfx.play("cast", global_position); main.fx_sprite("moon", global_position + Vector2(0, -16), 80.0, 1.4, {"grow": 0.4, "spin": -0.6})


func _condition_ended(cond: String) -> void:
	match cond:
		"raging":
			recalc()
			if not has_feat("extra_rage"):
				add_condition("fatigued", 4.0)
		"haze":
			add_condition("munchies", 8.0)
			bark("...anyone got snacks?")
			if randf() < 0.25 and main.draughts > 0:
				main.draughts -= 1
				main.float_text(global_position + Vector2(0, -20), "Puck ate a healing draught", Color(0.9, 0.7, 0.4))


func die() -> void:
	super.die()
	bark(["Nana...?", "Ugh.", "Tell them I was strong.", "..."][["puck", "brokk", "average", "sael"].find(hero_id)])


func dash_length() -> float:
	return 0.25 if hero_id != "average" else 0.2


func drink() -> void:
	Sfx.play("drink", global_position, -2.0)
	if main.draughts <= 0 or not can_act() or state != State.IDLE or hp >= max_hp:
		return
	main.draughts -= 1
	state = State.DRINK
	action_timer = 1.0


func _finish_drink() -> void:
	heal(int(max_hp * 0.4 * (1.5 if prop("mending") else 1.0)))


func bark(text: String) -> void:
	if bark_cd > 0.0:
		return
	bark_cd = 2.5
	main.float_text(global_position + Vector2(0, -24), text, Color(0.95, 0.9, 0.75), 1.8)


func use_attack() -> void:
	if state == State.IDLE:
		combo = 0
		start_action(basic_attack(0))
	elif state in [State.WINDUP, State.ACTIVE, State.RECOVERY] and action.has("combo"):
		var nxt: int = int(action["combo"]) + 1
		if nxt < max_combo() and not action.has("then"):
			action["then"] = basic_attack(nxt)


func use_special() -> void:
	var a := special()
	if a.size() > 0:
		start_action(a)


func use_cast() -> void:
	if state != State.IDLE:
		return
	var a := cast()
	if a.size() > 0:
		start_action(a)


# =====================================================================
# Player input + party AI
# =====================================================================

func _think(delta: float) -> void:
	_tick_cds(delta)
	if controlled:
		_player_input()
	else:
		_ai(delta)
	if hero_id == "puck" and has("haze"):
		poise = max(poise, poise_max * 0.8)


func _player_input() -> void:
	move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	aim = main.player_aim(self)
	blocking = Input.is_action_pressed("parry") and state == State.IDLE and parry_timer <= 0.0
	if Input.is_action_just_pressed("attack"):
		use_attack()
	if Input.is_action_just_pressed("special"):
		use_special()
	if Input.is_action_just_pressed("cast"):
		use_cast()
	if Input.is_action_just_pressed("dash"):
		start_dash(move_input)
	if Input.is_action_just_pressed("parry"):
		start_parry()
	if Input.is_action_just_pressed("ability_1"):
		ability(1)
	if Input.is_action_just_pressed("ability_2"):
		ability(2)
	if Input.is_action_just_pressed("ability_3"):
		ability(3)
	if Input.is_action_just_pressed("drink"):
		drink()


func _ai(delta: float) -> void:
	move_input = Vector2.ZERO
	blocking = false
	think_t -= delta
	var leader: Hero = main.leader
	if leader == null or leader == self:
		leader = self
	var command: String = main.command
	var dist_leader := global_position.distance_to(leader.global_position)

	# Average doesn't dodge, he parries (or takes it on the chin) right as a melee blow lands
	if hero_id == "average" and dodge_cd <= 0.0 and state == State.IDLE and main.danger_timer(self) < 0.09:
		dodge_cd = 0.8
		if randf() < 0.45:
			start_parry()
			return
	# Read the fight: dodge telegraphs sideways/out, sidestep bolts, step out of fire and dust.
	# Brokk and Eowilas are careful; Puck is unbothered but not suicidal; Average would rather parry.
	if dodge_cd <= 0.0 and state == State.IDLE and command != "hold":
		var skill: float = {"average": 0.4, "puck": 0.55, "brokk": 0.85, "sael": 0.8}[hero_id]
		var t: Dictionary = main.threat_dodge(self, 0.3 + skill * 0.15)
		if t["dir"] != Vector2.ZERO:
			if t["dash"]:
				dodge_cd = 0.9
				if randf() < skill and stamina > 16.0:
					start_dash(t["dir"])
					return
			else:
				move_input = t["dir"]
				return
	if not can_act() or state != State.IDLE:
		if ai_target != null and not ai_target.is_dead():
			aim = (ai_target.global_position - global_position).normalized()
		return

	# Regroup if too far (along the leader's trail if the way isn't clear)
	if dist_leader > 160.0:
		move_input = (main.follow_point(self, leader.global_position) - global_position).normalized()
		return

	# Retreat when hurt (Average out of pride, Puck because he isn't worried: never)
	if hp < max_hp * 0.25 and hero_id in ["brokk", "sael"] and command != "hold":
		var sael: Hero = main.hero("sael")
		var safe: Vector2 = (sael.global_position if sael != self and not sael.is_dead() else leader.global_position)
		if main.nearest_enemy_dist(global_position) > 40.0 and main.draughts > 1 and main.tactics_draughts:
			drink()
			return
		move_input = (safe - global_position).normalized() if global_position.distance_to(safe) > 12.0 else Vector2.ZERO
		move_input += main.flee_vector(self) * 0.8
		return

	if hero_id != "average" and dodge_cd <= 0.0 and main.enemies_within(global_position, 30.0) >= 3 and stamina > 20.0:
		dodge_cd = 1.5
		start_dash(main._safe_dir(global_position, main.flee_vector(self)))
		return
	# anyone in real trouble drinks, if nothing is right on top of them
	if hp < max_hp * 0.2 and main.tactics_draughts and main.draughts > 1 and cd("panic_drink") <= 0.0 and main.nearest_enemy_dist(global_position) > 28.0:
		cds["panic_drink"] = 6.0
		drink()
		return

	if think_t <= 0.0:
		think_t = 0.2
		ai_target = _choose_target(leader, command)

	if leader == self and main.autotest and ai_target == null:
		var goal: Variant = main.autotest_goal()
		if goal != null:
			move_input = (goal - global_position).normalized()
			facing = move_input
		return
	if command == "fall_back" or ai_target == null:
		_follow(leader)
		return

	if brain != null:
		brain.tick()
	else:
		match hero_id:
			"average": _ai_average(command)
			"puck": _ai_puck(command, leader)
			"brokk": _ai_brokk(command)
			"sael": _ai_sael(command, leader)
	move_input += main.separation(self) * 0.6
	if command == "hold":
		move_input = Vector2.ZERO


func _choose_target(leader: Hero, command: String) -> Combatant:
	if command == "attack_target" and main.focus_target != null and not main.focus_target.is_dead():
		return main.focus_target
	var center := leader.global_position
	var reach_r := 130.0
	var best: Combatant = null
	var best_score := -INF
	for e in main.enemies:
		if e.is_dead():
			continue
		var d1: float = e.global_position.distance_to(center)
		var d2: float = e.global_position.distance_to(global_position)
		if d1 > reach_r and d2 > 90.0 and not (e.target != null and d2 < 220.0):
			continue
		# companions leave enemies that haven't noticed us alone, unless the leader picks the fight
		if self != leader and not e.aware and not e.damaged_by.has(leader) and d2 > 40.0:
			continue
		var score: float = -d2
		score += (1.0 - float(e.hp) / e.max_hp) * 45.0   # finish what's nearly dead
		if e.state == Combatant.State.WINDUP and e.action.get("is_spell", false):
			score += 50.0                                   # casters mid-spell first
		if hero_id == "brokk" and e.kind == "cultist":
			score += 200.0
		if hero_id == "brokk" and grudges.has(e.kind):
			score += 40.0
		if e == main.focus_target:
			score += 60.0
		if e.target == self and hero_id == "average":
			score += 30.0
		if score > best_score:
			best_score = score
			best = e
	return best


func _follow(leader: Hero) -> void:
	if leader == self:
		return
	var fwd: Vector2 = leader.facing
	var side := fwd.orthogonal()
	var slot: Vector2 = {
		"average": fwd * 12 + side * 16,
		"puck": -fwd * 14 - side * 18,
		"brokk": -fwd * 26 + side * 10,
		"sael": -fwd * 22 - side * 4,
	}[hero_id]
	var goal: Vector2 = main.follow_point(self, leader.global_position + slot)
	var to := goal - global_position
	if to.length() > 6.0:
		move_input = to.normalized() * clamp(to.length() / 30.0, 0.3, 1.0)
	move_input += main.separation(self) * 0.5
	if move_input.length() > 0.05:
		facing = move_input.normalized()


func _approach_and_hit(reach: float) -> void:
	var to := ai_target.global_position - global_position
	aim = to.normalized()
	if to.length() > reach + ai_target.radius - 2.0:
		move_input = to.normalized()
	else:
		facing = aim
		if stamina > 15.0:
			use_attack()


func _ai_average(command: String) -> void:
	if main.danger_timer(self) < 0.45 and randf() < 0.5:
		return  # hold still and wait for the parry window
	var near: int = main.enemies_within(global_position, 36.0)
	if main.tactics_rage and cd("rage") <= 0.0 and near >= 1:
		ability(1)
	if glory >= 100.0:
		ability(2)
	if main.enemies_within(global_position, 44.0) >= 2 and cd("slam") <= 0.0 and stamina > 30.0:
		use_cast()
		return
	if ai_target is Enemy and ai_target.has("staggered") and stamina > 35.0 and global_position.distance_to(ai_target.global_position) < 28.0:
		aim = (ai_target.global_position - global_position).normalized()
		use_special()
		return
	_approach_and_hit(20.0)


func _ai_puck(command: String, leader: Hero) -> void:
	var cluster: int = main.enemies_within(ai_target.global_position, 40.0)
	var worth: bool = cluster >= 2 or ai_target.max_hp > 30 or ai_target.kind == "cultist"
	if main.tactics_herbs and herbs > 1 and cd("herb_ai") <= 0.0 and worth and not ai_target.has("asleep") and global_position.distance_to(ai_target.global_position) < 90.0:
		cds["herb_ai"] = 7.0
		herb_index = 0 if cluster >= 2 else [0, 1, 2].pick_random()
		aim = (ai_target.global_position - global_position).normalized()
		use_cast()
		return
	# try to flank: stand on the far side of the target from the leader
	if leader != self and leader.global_position.distance_to(ai_target.global_position) < 40.0:
		var flank_pos: Vector2 = ai_target.global_position + (ai_target.global_position - leader.global_position).normalized() * 16.0
		if global_position.distance_to(flank_pos) > 10.0 and global_position.distance_to(ai_target.global_position) > 14.0:
			move_input = (flank_pos - global_position).normalized()
			return
	_approach_and_hit(18.0)


func _ai_brokk(command: String) -> void:
	var to := ai_target.global_position - global_position
	aim = to.normalized()
	var nearest: float = main.nearest_enemy_dist(global_position)
	if nearest < 55.0 and not has("stand"):
		move_input = main.flee_vector(self)
		if nearest < 25.0 and dodge_cd <= 0.0:
			dodge_cd = 1.2
			start_dash(main.flee_vector(self))
		return
	if to.length() > 170.0:
		move_input = to.normalized()
		return
	facing = aim
	if arcane_pool > 0 and cd("spell_ai") <= 0.0 and (ai_target.max_hp > 30 or ai_target.kind == "cultist"):
		cds["spell_ai"] = 4.0
		spell_index = 0 if not ai_target.is_boss else 1
		use_cast()
	elif stamina > 12.0:
		use_attack()


func _ai_sael(command: String, leader: Hero) -> void:
	# Heal
	var hurt := 0
	for h in main.heroes:
		if not h.is_dead() and h.hp < h.max_hp * (float(main.tactics_heal) / 100.0):
			hurt += 1
			if h.global_position.distance_to(global_position) > 50.0:
				move_input = (h.global_position - global_position).normalized()
				return
	if hurt > 0 and slots > 0:
		use_cast()
		return
	# Revive
	if slots > 0:
		var fallen: Hero = main.nearest_fallen(global_position, 200.0)
		if fallen != null and main.nearest_enemy_dist(fallen.global_position) > 30.0:
			if global_position.distance_to(fallen.global_position) > 60.0:
				move_input = (fallen.global_position - global_position).normalized()
			else:
				ability(3)
			return
	# Free allies
	for h in main.heroes:
		if not h.is_dead() and h != self and (h.has("asleep") or h.has("confused") or h.has("prone")) and cd("chains") <= 0.0:
			if h.global_position.distance_to(global_position) < 60.0:
				ability(2)
				return
	# Silence a caster
	var caster: Combatant = main.casting_enemy(global_position, 120.0)
	if caster != null and cd("silence") <= 0.0:
		ai_target = caster
		ability(1)
		return
	# Weak in melee: stay behind the leader, poke only what is in reach
	var behind := leader.global_position - leader.facing * 26.0
	if leader != self and global_position.distance_to(behind) > 14.0:
		move_input = (behind - global_position).normalized()
	if global_position.distance_to(ai_target.global_position) < 20.0 + ai_target.radius:
		aim = (ai_target.global_position - global_position).normalized()
		use_attack()
	elif stamina > 30.0 and global_position.distance_to(ai_target.global_position) < 120.0 and cd("throw_ai") <= 0.0:
		cds["throw_ai"] = 3.0
		aim = (ai_target.global_position - global_position).normalized()
		use_special()


# =====================================================================
# Drawing
# =====================================================================

func _draw_body() -> void:
	super._draw_body()


func _draw() -> void:
	super._draw()
	if state == State.DEAD:
		return
	if has("haze"):
		draw_circle(Vector2(0, -sprite_h * 0.5), 14 + sin(anim_t * 4.0) * 2.0, Color.from_hsv(fmod(anim_t * 0.3, 1.0), 0.6, 1.0, 0.18))
	if has("ward"):
		draw_arc(Vector2(0, -sprite_h * 0.5), 15, 0, TAU, 24, Color(0.6, 0.8, 1.0, 0.8), 1.0)
	if has("raging"):
		draw_arc(Vector2(0, -sprite_h * 0.5), 13 + sin(anim_t * 9.0), 0, TAU, 20, Color(0.9, 0.15, 0.05, 0.5), 1.0)
	if controlled:
		var y := -sprite_h - 9.0
		draw_colored_polygon(PackedVector2Array([Vector2(-3, y), Vector2(3, y), Vector2(0, y + 3)]), Color(0.95, 0.85, 0.5))


func _process(_delta: float) -> void:
	if nana_sprite != null:
		# Nana is painted into Puck's concept art; the floating sprite only shows when she steps in
		nana_sprite.visible = not is_dead()
		var side := -1.0 if facing.x >= 0.0 else 1.0
		nana_pose_t -= _delta
		var pose := nana_pose if nana_pose_t > 0.0 else ("fly" if velocity.length() > 70.0 else "idle")
		var nt := Art.prop("nana_" + pose)
		if nt != null:
			nana_sprite.texture = nt
			# the sheet faces right; she looks the way Puck looks
			nana_sprite.flip_h = facing.x < 0.0
		nana_sprite.position = Vector2(side * (16.0 if pose == "fly" else 13.0), -sprite_h - 2.0 + sin(anim_t * 2.0) * 2.0)
		nana_sprite.modulate.a = 0.55 + sin(anim_t * 1.3) * 0.15 + (0.3 if has("ward") else 0.0)
	if dome_sprite != null:
		var shielded := not is_dead() and (has("stand") or has("ward"))
		dome_sprite.visible = shielded
		if shielded:
			dome_sprite.modulate = Color(0.8, 0.9, 1.1, 0.55 + sin(anim_t * 3.0) * 0.12) if has("stand") else Color(0.7, 0.85, 1.0, 0.5 + sin(anim_t * 2.0) * 0.1)
	if moth_sprite != null:
		moth_sprite.visible = not is_dead()
		moth_sprite.position = Vector2(cos(anim_t * 2.5) * 12.0, -sprite_h + sin(anim_t * 2.5) * 5.0)
		moth_sprite.texture = Art.prop("moth_%d" % (int(anim_t * 8.0) % 2))


func figure_palette() -> Dictionary:
	match hero_id:
		"average": return {"skin": Color(0.66, 0.48, 0.38), "cloth": Color(0.42, 0.30, 0.20), "cloth2": Color(0.22, 0.17, 0.13), "hair": Color(0.25, 0.14, 0.08)}
		"puck": return {"skin": Color(0.72, 0.64, 0.52), "cloth": Color(0.24, 0.32, 0.24), "cloth2": Color(0.30, 0.24, 0.16), "hair": Color(0.45, 0.30, 0.55)}
		"brokk": return {"skin": Color(0.64, 0.46, 0.36), "cloth": Color(0.36, 0.36, 0.38), "cloth2": Color(0.28, 0.20, 0.14), "hair": Color(0.78, 0.40, 0.14)}
		"sael": return {"skin": Color(0.78, 0.74, 0.70), "cloth": Color(0.10, 0.10, 0.13), "cloth2": Color(0.55, 0.55, 0.62), "hair": Color(0.85, 0.85, 0.9)}
	return super.figure_palette()


func _draw_weapon(bob: float) -> void:
	if hero_id == "brokk":
		# the beard
		var hy := -radius * 2.45
		draw_rect(Rect2(-radius * 0.5, hy + radius * 0.6, radius, radius * 0.9), Color(0.78, 0.40, 0.14))
	var hand := Vector2(facing.x * radius * 0.8, -radius + bob)
	var swing := 0.0
	if state == State.WINDUP:
		swing = -1.0
	elif state == State.ACTIVE:
		swing = 0.9
	var dir := aim.rotated(swing) if state != State.IDLE else facing
	match hero_id:
		"average":
			draw_line(hand, hand + dir * 14.0, Color(0.3, 0.22, 0.15), 2.0)
			draw_rect(Rect2(hand + dir * 13.0 - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.55, 0.55, 0.58))
		"puck":
			var thrust := 6.0 if state == State.ACTIVE else 0.0
			draw_line(hand, hand + aim * (13.0 + thrust) if state != State.IDLE else hand + facing * 12.0, Color(0.85, 0.85, 0.9), 1.0)
		"brokk":
			var c := hand + aim * 3.0
			draw_arc(c, 6.0, aim.angle() - 1.2, aim.angle() + 1.2, 8, Color(0.45, 0.3, 0.15), 1.0)
		"sael":
			var p := hand + dir * 6.0
			draw_line(p - Vector2(2, 0), p + Vector2(2, 0), Color(0.8, 0.8, 0.9), 1.0)
			draw_line(p - Vector2(0, 2), p + Vector2(0, 2), Color(0.8, 0.8, 0.9), 1.0)
