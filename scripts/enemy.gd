class_name Enemy
extends Combatant
## Enemies: PF1e stat blocks + simple aggressive AI with Hades-style telegraphs.

var kind := "ghoul"
var target: Combatant = null
var attack_cd := 1.0
var think_t := 0.0
var cr := 1
var xp := 100
var enraged := false
var strafe := 1.0
var home := Vector2.ZERO
const BOSSES := ["iron_brother", "mirror_wraith", "shadow_moth", "dragon"]
var summoner: Combatant = null
var minions: Array = []
var phase := 0
var special_cd := 6.0
var dmg_up := 0
var aware := true           # open areas: enemies idle at their posts until they notice the party
var post := Vector2.ZERO
var leash := 9999.0
var wander_t := 0.0
var wander_to := Vector2.ZERO


var variant := ""             # "kind@variant" in an encounter list: same body, new name and tune


func setup(k: String) -> void:
	if "@" in k:
		variant = k.get_slice("@", 1)
		k = k.get_slice("@", 0)
	kind = k
	team = "enemy"
	sprite_id = k
	# some cultists are moth horrors: same spells, DorkTeach's winged horror art
	if k == "cultist" and Art.hd_has("moth_horror") and randf() < 0.4:
		sprite_id = "moth_horror"
	strafe = 1.0 if randf() < 0.5 else -1.0
	match k:
		"ghoul":
			display_name = "Mire Ghoul"
			max_hp = 18; ac = 15; flat_ac = 12; bab = 2
			saves = {"fort": 2, "ref": 2, "will": 2}
			speed = 52.0; radius = 6.0; poise_max = 18.0
			color = Color(0.36, 0.40, 0.30)
			xp = 135
		"cultist":
			display_name = "Hush Cultist"
			max_hp = 14; ac = 13; flat_ac = 11; bab = 1
			saves = {"fort": 1, "ref": 1, "will": 5}
			speed = 45.0; radius = 6.0; poise_max = 12.0
			color = Color(0.25, 0.18, 0.32)
			xp = 200
		"brute":
			display_name = "Bog Brute"
			max_hp = 60; ac = 16; flat_ac = 14; bab = 5
			saves = {"fort": 7, "ref": 1, "will": 1}
			speed = 38.0; radius = 10.0; poise_max = 70.0
			color = Color(0.42, 0.30, 0.24)
			xp = 400
		"iron_brother":
			display_name = "The Iron Brother"
			max_hp = 220; ac = 18; flat_ac = 16; bab = 8
			saves = {"fort": 9, "ref": 3, "will": 5}
			speed = 44.0; radius = 14.0; poise_max = 140.0
			color = Color(0.32, 0.30, 0.31)
			xp = 1200
		"mirror_wraith":
			display_name = "The Glass Mourner"
			max_hp = 680; ac = 19; flat_ac = 15; bab = 9
			saves = {"fort": 6, "ref": 8, "will": 11}
			speed = 52.0; radius = 11.0; poise_max = 110.0
			color = Color(0.7, 0.72, 0.8)
			xp = 2400; hover = 3.0
		"mirror_clone":
			display_name = "Mirror Image"
			sprite_id = "mirror_wraith"
			max_hp = 1; ac = 19; flat_ac = 15; bab = 6
			saves = {"fort": 0, "ref": 0, "will": 0}
			speed = 52.0; radius = 11.0; poise_max = 1.0
			color = Color(0.7, 0.72, 0.8)
			xp = 0; hover = 3.0
		"shadow_moth":
			display_name = "The Mother of Moths"
			max_hp = 720; ac = 18; flat_ac = 14; bab = 9
			saves = {"fort": 8, "ref": 10, "will": 8}
			speed = 64.0; radius = 15.0; poise_max = 130.0
			color = Color(0.1, 0.08, 0.14)
			xp = 2800; hover = 16.0
		"moth_swarm":
			display_name = "Shade Moth"
			sprite_id = "shadow_moth"
			max_hp = 10; ac = 15; flat_ac = 11; bab = 4
			saves = {"fort": 1, "ref": 5, "will": 1}
			speed = 86.0; radius = 5.0; poise_max = 4.0
			color = Color(0.1, 0.08, 0.14)
			xp = 60; hover = 9.0
		"dragon":
			display_name = "Ashmaw the Chained"
			max_hp = 1150; ac = 21; flat_ac = 18; bab = 12
			saves = {"fort": 12, "ref": 7, "will": 9}
			speed = 36.0; radius = 24.0; poise_max = 320.0
			color = Color(0.2, 0.16, 0.14)
			xp = 6000
	is_boss = k in BOSSES
	# beyond each rift everything is meaner
	if Run.act >= 2 and k in ["ghoul", "cultist", "brute"]:
		var tier: int = Run.act - 1
		display_name = (["", "Ash ", "Frost "][min(tier, 2)] + {"ghoul": "Ghoul", "cultist": "Cultist", "brute": "Brute"}[k])
		if Run.act == 2 and k == "cultist":
			display_name = "Cinder Cultist"
		max_hp = int(max_hp * (1.0 + 0.7 * tier))
		ac += 2 * tier; flat_ac += 2 * tier; bab += 3 * tier; dmg_up = 2 * tier
		poise_max *= 1.0 + 0.3 * tier
		xp = int(xp * (1.0 + 0.8 * tier))
		modulate = Color(0.86, 0.8, 0.78) if tier == 1 else Color(0.78, 0.88, 1.05)
	if variant != "":
		_apply_variant(variant)
	setup_common()
	max_stamina = 999.0
	stamina = 999.0
	if k == "moth_swarm" and sprite != null:
		sprite_scale = 0.065
		sprite_h = float(Art.hd_pose(sprite_id, "idle")["foot"][1]) * sprite_scale * 0.85
	if k == "mirror_clone":
		modulate = Color(0.75, 0.9, 1.1, 0.62)
	if variant == "hollowmoth" and sprite != null:
		# the final boss: the same shadow, grown enormous on stolen starlight
		sprite_scale *= 1.6
		sprite_h *= 1.6
		radius *= 1.35
		hover = 26.0
		poise_max *= 1.5


func _think(delta: float) -> void:
	move_input = Vector2.ZERO
	attack_cd -= delta
	think_t -= delta
	if not can_act():
		return
	if not enraged and kind == "iron_brother" and hp < max_hp / 2.0:
		enraged = true
		speed *= 1.3
		main.float_text(global_position + Vector2(0, -40), "THE IRON BROTHER ROARS", Color(1, 0.3, 0.2))
		main.shake(6.0)
	special_cd -= delta
	if kind == "dragon" and phase == 0 and hp < max_hp * 0.55:
		phase = 1
		enraged = true
		speed *= 1.25
		main.float_text(global_position + Vector2(0, -90), "THE CHAINS BREAK", Color(1, 0.45, 0.15), 2.0)
		main.shake(8.0)
		Sfx.play("roar", global_position, 2.0, 0.0)
		special_cd = 1.0
	if kind == "shadow_moth" and phase == 0 and hp < max_hp * 0.5:
		phase = 1
		enraged = true
		speed *= 1.2
		main.float_text(global_position + Vector2(0, -50), "THE HOLLOWMOTH DRINKS THE STARS" if variant == "hollowmoth" else "THE MOTHER DARKENS", Color(0.7, 0.5, 1.0), 2.0)
		main.shake(5.0)
	if not aware:
		_idle_think(delta)
		return
	# don't chase forever: past the leash, walk back to the post
	if global_position.distance_to(home) > leash and not is_boss:
		target = null
		move_input = (post - global_position).normalized()
		if randf() < 0.01:
			aware = false
		move_input += main.separation(self) * 0.8
		return
	if think_t <= 0.0 or target == null or target.is_dead():
		think_t = 0.4
		target = _pick_target()
	if target == null:
		return
	if state != State.IDLE:
		aim = (target.global_position - global_position).normalized() if not action.get("lock_aim", true) else aim
		return
	var to := target.global_position - global_position
	var dist := to.length()
	aim = to.normalized()
	match kind:
		"cultist":
			if has("silenced"):
				_melee_ai(to, dist, 14.0, _claw())
			elif dist < 70.0:
				move_input = -to.normalized()
			elif dist > 140.0:
				move_input = to.normalized()
			else:
				move_input = to.normalized().orthogonal() * strafe * 0.6
				if attack_cd <= 0.0:
					_cast_bolt()
		"brute":
			if attack_cd <= 0.0 and dist < 34.0:
				if randf() < 0.5:
					_do(_slam())
				else:
					_do(_sweep(1.0))
			else:
				move_input = to.normalized()
		"iron_brother":
			if attack_cd <= 0.0:
				if dist < 40.0:
					_do(_sweep(1.3) if randf() < 0.6 else _slam())
				elif dist < 150.0 and randf() < 0.4:
					_do(_leap(target.global_position))
				else:
					move_input = to.normalized()
			else:
				move_input = to.normalized() * (0.6 if dist > 30.0 else 0.0)
		"mirror_wraith":
			if phase < 2 and hp < max_hp * (0.66 if phase == 0 else 0.33):
				phase += 1
				_do(_mirror_images())
			elif attack_cd <= 0.0:
				var r := randf()
				if dist > 70.0 or r < 0.4:
					_do(_shard_volley(5))
				elif r < 0.75:
					_do(_blink(target))
				else:
					_do(_claw())
			elif dist < 60.0:
				move_input = -to.normalized()
			elif dist > 130.0:
				move_input = to.normalized()
			else:
				move_input = to.normalized().orthogonal() * strafe * 0.7
		"mirror_clone":
			if attack_cd <= 0.0 and dist < 160.0:
				_do(_shard_volley(1))
				attack_cd = randf_range(2.0, 3.2)
			else:
				move_input = to.normalized().orthogonal() * strafe * 0.7 + (to.normalized() if dist > 120.0 else Vector2.ZERO)
		"shadow_moth":
			var alive_moths := minions.filter(func(m): return is_instance_valid(m) and not m.is_dead()).size()
			star_cd -= delta
			if variant == "hollowmoth" and enraged and star_cd <= 0.0:
				star_cd = 7.0
				_do(_ember_rain())
			elif special_cd <= 0.0 and alive_moths < (3 if variant == "hollowmoth" else 2):
				special_cd = 13.0 if not enraged else 9.0
				_do(_brood())
			elif attack_cd <= 0.0:
				var r2 := randf()
				if dist > 60.0 and dist < 170.0 and r2 < 0.45:
					_do(_dive())
				elif r2 < 0.75 or dist >= 170.0:
					_do(_dust(target.global_position))
				elif dist < 40.0:
					_do(_sweep(1.1))
				else:
					move_input = to.normalized()
			else:
				# circle the party at a wary distance
				move_input = to.normalized().orthogonal() * strafe + to.normalized() * (0.6 if dist > 90.0 else -0.5)
		"moth_swarm":
			_melee_ai(to, dist, 10.0, _nip())
		"dragon":
			if enraged and special_cd <= 0.0:
				special_cd = 8.0
				_do(_ember_rain())
			elif attack_cd <= 0.0:
				var r3 := randf()
				if dist < radius + 30.0:
					if r3 < 0.45:
						_do(_bite())
					elif r3 < 0.8:
						_do(_sweep(2.0))
					else:
						_do(_gust())
				elif dist < 190.0 and r3 < 0.5:
					_do(_breath())
				else:
					move_input = to.normalized()
			else:
				move_input = to.normalized() * (0.5 if dist > radius + 24.0 else 0.0)
		_:
			_melee_ai(to, dist, 16.0, _claw())
	move_input += main.separation(self) * 0.8


## Unaware: shuffle around the post; wake when a hero gets close, when hurt, or when a friend shouts.
func _idle_think(delta: float) -> void:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(1.5, 4.0)
		wander_to = post + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 30.0)
	var to := wander_to - global_position
	move_input = to.normalized() * 0.3 if to.length() > 4.0 else Vector2.ZERO
	if to.length() > 4.0:
		facing = to.normalized()
	var near: Combatant = main.nearest_hero(global_position)
	var sight := 130.0 if not has("asleep") else 0.0
	if not damaged_by.is_empty() or (near != null and near.global_position.distance_to(global_position) < sight):
		alert()


func alert() -> void:
	if aware:
		return
	aware = true
	think_t = 0.0
	attack_cd = randf_range(0.3, 0.9)
	main.float_text(global_position + Vector2(0, -sprite_h - 6), "!", Color(1.0, 0.4, 0.3), 0.8)
	# shout to the others nearby
	for e in main.enemies:
		if e != self and not e.is_dead() and not e.aware and e.global_position.distance_to(global_position) < 110.0:
			e.call_deferred("alert")


func _melee_ai(to: Vector2, dist: float, reach: float, a: Dictionary) -> void:
	if dist > reach + target.radius:
		move_input = to.normalized()
	elif attack_cd <= 0.0:
		_do(a)
	else:
		move_input = to.normalized().orthogonal() * strafe * 0.4


func _pick_target() -> Combatant:
	if has("confused"):
		return main.nearest_any(self)
	var taunter: Combatant = main.taunter()
	if taunter != null and taunter.global_position.distance_to(global_position) < 160.0:
		return taunter
	return main.nearest_hero(global_position)


func _do(a: Dictionary) -> void:
	aim = (target.global_position - global_position).normalized()
	facing = aim
	if has("confused"):
		a["any_team"] = true
	if start_action(a):
		attack_cd = randf_range(0.5, 1.2) * (0.7 if enraged else 1.0)


func _claw() -> Dictionary:
	return {
		"name": "claw", "windup": 0.55, "active": 0.08, "recovery": 0.45,
		"shape": "arc", "reach": 16.0, "arc": 80.0, "lock_aim": true, "poise_dmg": 12.0,
		"attack": {"name": "claw", "bonus": bab + 3, "dice_n": 1, "dice_s": 8, "dmg_bonus": 3 + dmg_up},
	}


func _sweep(scale: float) -> Dictionary:
	return {
		"name": "sweep", "windup": 0.8 / scale, "active": 0.1, "recovery": 0.7,
		"shape": "arc", "reach": 26.0 * scale, "arc": 140.0, "lock_aim": true, "poise_dmg": 30.0,
		"heavy": true, "knockback": 90.0,
		"attack": {"name": "sweep", "bonus": bab + 4, "dice_n": 2, "dice_s": 6, "dmg_bonus": 4 + int(scale * 2) + dmg_up},
	}


func _slam() -> Dictionary:
	var a := {
		"name": "slam", "windup": 1.0, "active": 0.1, "recovery": 0.9,
		"shape": "circle", "radius": radius * 3.2, "lock_aim": true, "poise_dmg": 45.0,
		"heavy": true, "knockback": 120.0,
		"attack": {"name": "slam", "bonus": bab + 4, "dice_n": 2, "dice_s": 8, "dmg_bonus": 5 + dmg_up},
	}
	a["_point"] = global_position
	return a


func _leap(point: Vector2) -> Dictionary:
	var a := {
		"name": "leap slam", "windup": 1.1, "active": 0.12, "recovery": 1.0,
		"shape": "circle", "radius": 38.0, "lock_aim": true, "poise_dmg": 50.0,
		"heavy": true, "knockback": 140.0,
		"attack": {"name": "leap slam", "bonus": bab + 4, "dice_n": 3, "dice_s": 8, "dmg_bonus": 6},
	}
	a["_point"] = point
	a["on_start"] = func() -> void: pass
	a["custom"] = func() -> void:
		position = main.keep_walkable(position, point, radius) if main.is_walkable(point, radius) else position
		for t in main.targets_in_area(self, a):
			strike(t, a)
		main.shake(6.0)
		main.blood(point, 4)
		Sfx.play("slam", point); main.fx_sprite("crater", point, 90.0, 2.0, {"ground": true, "grow": 0.1, "hold": 0.6, "tint": Color(1, 0.8, 0.7)})
	return a


func _cast_bolt() -> void:
	var a := {
		"name": "hush bolt", "windup": 1.2, "active": 0.05, "recovery": 0.6,
		"shape": "line", "reach": 150.0, "width": 4.0, "lock_aim": true, "is_spell": true,
		"attack": {"name": "hush bolt", "bonus": 5, "dice_n": 2, "dice_s": 6, "dmg_bonus": 2},
	}
	a["custom"] = func() -> void:
		if has("silenced"):
			main.float_text(global_position, "silenced", Color(0.6, 0.6, 0.8))
			return
		main.spawn_projectile(self, global_position + Vector2(0, -8), facing, 170.0, a, Color(0.5, 0.3, 0.9))
	_do(a)
	attack_cd = randf_range(1.8, 2.6)


# ---------- Act II bosses ----------

func _shard_volley(n: int) -> Dictionary:
	var a := {
		"name": "glass shards", "windup": 1.0 if n > 1 else 1.3, "active": 0.05, "recovery": 0.6,
		"shape": "line", "reach": 170.0, "width": 10.0 if n > 1 else 4.0, "lock_aim": true, "is_spell": true,
		"attack": {"name": "glass shard", "bonus": bab + 2, "dice_n": 2, "dice_s": 6, "dmg_bonus": 3 if n > 1 else 0},
	}
	a["custom"] = func() -> void:
		if has("silenced"):
			main.float_text(global_position, "silenced", Color(0.6, 0.6, 0.8))
			return
		Sfx.play("shatter", global_position, -6.0)
		for i in n:
			var ang := (i - (n - 1) / 2.0) * 0.17
			main.spawn_projectile(self, global_position + Vector2(0, -14), facing.rotated(ang), 185.0, a, Color(0.75, 0.9, 1.0))
	return a


func _blink(t: Combatant) -> Dictionary:
	var a := {"name": "blink", "windup": 0.45, "active": 0.05, "recovery": 0.15, "shape": "circle", "radius": 0.0,
		"telegraph": false, "is_attack": false, "cast_anim": true}
	a["custom"] = func() -> void:
		var behind := t.global_position - t.facing * 24.0
		if not main.is_walkable(behind, radius):
			behind = t.global_position + t.facing.orthogonal() * 24.0
		if main.is_walkable(behind, radius):
			main.ring(global_position, 22.0, Color(0.7, 0.85, 1.0))
			Sfx.play("dash", global_position, -2.0)
			position = behind
			main.ring(global_position, 22.0, Color(0.7, 0.85, 1.0))
		attack_cd = 0.1
	return a


func _mirror_images() -> Dictionary:
	var a := {"name": "mirror image", "windup": 0.9, "active": 0.05, "recovery": 0.4, "shape": "circle", "radius": 0.0,
		"telegraph": false, "is_attack": false, "is_spell": true}
	a["custom"] = func() -> void:
		Sfx.play("shatter", global_position, 0.0)
		main.float_text(global_position + Vector2(0, -50), "Mirror Image", Color(0.75, 0.9, 1.0), 1.4)
		var spots: Array = []
		for i in 3:
			spots.append(home + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 80.0))
		for i in 2:
			main.spawn_minion("mirror_clone", spots[i], self)
			main.ring(spots[i], 18.0, Color(0.75, 0.9, 1.0))
		# and she slips into the third reflection, so the heroes lose track of her
		if main.is_walkable(spots[2], radius):
			position = spots[2]
	return a


func _nip() -> Dictionary:
	return {
		"name": "nip", "windup": 0.4, "active": 0.06, "recovery": 0.35,
		"shape": "arc", "reach": 10.0, "arc": 90.0, "lock_aim": true, "poise_dmg": 4.0, "telegraph": false,
		"attack": {"name": "nip", "bonus": bab + 2, "dice_n": 1, "dice_s": 4, "dmg_bonus": 1},
	}


func _dive() -> Dictionary:
	var a := {
		"name": "dive", "windup": 0.95, "active": 0.1, "recovery": 0.8,
		"shape": "line", "reach": 150.0, "width": 14.0, "lock_aim": true, "poise_dmg": 30.0, "heavy": true, "knockback": 100.0, "dodge_line": true,
		"attack": {"name": "dive", "bonus": bab + 4, "dice_n": 2, "dice_s": 8, "dmg_bonus": 5},
	}
	a["custom"] = func() -> void:
		Sfx.play("wings", global_position, 0.0)
		for t in main.targets_in_area(self, a):
			strike(t, a)
		var end: Vector2 = global_position + facing * 140.0
		position = main.keep_walkable(position, end, radius) if main.is_walkable(end, radius) else position
		main.fx_sprite("moths", global_position, 50.0, 0.8, {"spin": 1.0, "grow": 0.4})
	return a


func _dust(point: Vector2) -> Dictionary:
	var a := {
		"name": "moth dust", "windup": 1.1, "active": 0.05, "recovery": 0.6, "is_spell": true, "is_attack": false, "cast_anim": true,
		"shape": "circle", "radius": 44.0, "lock_aim": true,
	}
	a["_point"] = point
	a["custom"] = func() -> void:
		Sfx.play("wings", point, -4.0)
		main.spawn_cloud(self, point, 44.0, 5.0, "Dust", 16)
	return a


func _brood() -> Dictionary:
	var a := {"name": "brood", "windup": 1.0, "active": 0.05, "recovery": 0.5, "shape": "circle", "radius": 0.0,
		"telegraph": false, "is_attack": false, "cast_anim": true}
	a["custom"] = func() -> void:
		Sfx.play("wings", global_position, 2.0)
		main.float_text(global_position + Vector2(0, -50), "the brood wakes", Color(0.7, 0.55, 0.95), 1.2)
		for i in (3 if not enraged else 4):
			main.spawn_minion("moth_swarm", global_position + Vector2.from_angle(i * TAU / 3.0) * 26.0, self)
	return a


func _bite() -> Dictionary:
	return {
		"name": "bite", "windup": 0.75, "active": 0.08, "recovery": 0.6,
		"shape": "arc", "reach": radius + 22.0, "arc": 70.0, "lock_aim": true, "poise_dmg": 40.0, "heavy": true, "knockback": 60.0,
		"attack": {"name": "bite", "bonus": bab + 3, "dice_n": 2, "dice_s": 8, "dmg_bonus": 8},
	}


func _gust() -> Dictionary:
	var a := {
		"name": "wing gust", "windup": 0.9, "active": 0.1, "recovery": 0.8,
		"shape": "circle", "radius": radius + 48.0, "lock_aim": true, "poise_dmg": 50.0, "heavy": true, "knockback": 230.0,
		"attack": {"name": "wing gust", "bonus": bab + 2, "dice_n": 1, "dice_s": 6, "dmg_bonus": 2},
	}
	a["_point"] = global_position
	a["on_start"] = func() -> void: Sfx.play("wings", global_position, 3.0)
	return a


func _breath() -> Dictionary:
	var a := {
		"name": "fire breath", "windup": 1.4, "active": 0.1, "recovery": 1.0,
		"shape": "line", "reach": 190.0, "width": 18.0, "lock_aim": true, "poise_dmg": 30.0, "heavy": true, "dodge_line": true,
		"attack": {"name": "fire breath", "bonus": bab + 2, "dice_n": 3, "dice_s": 6, "dmg_bonus": 4},
	}
	a["on_start"] = func() -> void: Sfx.play("roar", global_position, -2.0, 0.1)
	a["custom"] = func() -> void:
		Sfx.play("breath", global_position, 2.0)
		main.shake(4.0)
		for t in main.targets_in_area(self, a):
			strike(t, a)
		var mouth: Vector2 = global_position + Vector2(0, -20)
		for i in 5:
			var p: Vector2 = global_position + facing * (40.0 + i * 36.0)
			if main.is_walkable(p, 0.0):
				main.spawn_cloud(self, p, 18.0, 4.5, "Fire", 18)
			main.fx_sprite("burst", mouth.lerp(p, 1.0), 34.0 + i * 6.0, 0.5 + i * 0.06, {"tint": Color(1.0, 0.5, 0.15), "grow": 0.5})
	return a


var star_cd := 3.0


func _ember_rain() -> Dictionary:
	var a := {"name": "ember rain", "windup": 1.0, "active": 0.05, "recovery": 0.6, "shape": "circle", "radius": 0.0,
		"telegraph": false, "is_attack": false, "cast_anim": true}
	a["on_start"] = func() -> void: Sfx.play("roar", global_position, 0.0, 0.0)
	a["custom"] = func() -> void:
		main.float_text(global_position + Vector2(0, -100), "the stars fall" if kind == "shadow_moth" else "ash falls burning", Color(1.0, 0.5, 0.2) if kind == "dragon" else Color(0.7, 0.8, 1.0), 1.4)
		for h in main.heroes:
			if h.is_dead():
				continue
			for i in 2:
				var p: Vector2 = h.global_position + (h.velocity * 0.6 if i == 0 else Vector2.from_angle(randf() * TAU) * randf_range(20.0, 50.0))
				if main.is_walkable(p, 0.0):
					main.spawn_ember(self, p, 24.0, 1.5 + randf() * 0.5, 18)
	return a


func die() -> void:
	super.die()
	for m in minions:
		if is_instance_valid(m) and not m.is_dead():
			m.die()
	if kind == "mirror_clone":
		Sfx.play("shatter", global_position, -3.0)
		main.ring(global_position, 16.0, Color(0.75, 0.9, 1.0))
		queue_free_later()


## Mirror images shatter: no corpse.
func queue_free_later() -> void:
	await get_tree().create_timer(0.4, false).timeout
	if is_instance_valid(self):
		visible = false


## Act III re-uses bodies with new names, colours and numbers.
const VARIANTS := {
	"warden": {"name": "The Lantern Warden", "tint": Color(0.7, 0.85, 1.15), "hp": 2.6, "bab": 4, "ac": 3, "xp": 3.0},
	"choir": {"name": "The Pale Choir", "tint": Color(1.15, 1.05, 0.8), "hp": 1.5, "bab": 3, "ac": 2, "xp": 1.6},
	"hollowmoth": {"name": "The Hollowmoth", "tint": Color(0.62, 0.72, 1.2), "hp": 3.0, "bab": 4, "ac": 3, "xp": 3.5},
	"starved": {"name": "Starved One", "tint": Color(0.75, 0.8, 1.0), "hp": 1.0, "bab": 0, "ac": 0, "xp": 1.0},
}


func _apply_variant(v: String) -> void:
	var d: Dictionary = VARIANTS.get(v, {})
	if d.is_empty():
		return
	display_name = d["name"]
	max_hp = int(max_hp * d["hp"])
	hp = max_hp
	bab += d["bab"]
	ac += d["ac"]
	flat_ac += d["ac"]
	xp = int(xp * d["xp"])
	modulate = d["tint"]


func _condition_ended(cond: String) -> void:
	if cond == "confused":
		target = null


func figure_palette() -> Dictionary:
	match kind:
		"ghoul": return {"skin": Color(0.42, 0.48, 0.38), "cloth": Color(0.30, 0.28, 0.22), "cloth2": Color(0.20, 0.18, 0.14), "hair": Color(0.15, 0.17, 0.12)}
		"cultist": return {"skin": Color(0.12, 0.08, 0.14), "cloth": Color(0.22, 0.14, 0.26), "cloth2": Color(0.12, 0.08, 0.14), "hair": Color(0.22, 0.14, 0.26)}
		"brute": return {"skin": Color(0.48, 0.38, 0.32), "cloth": Color(0.38, 0.24, 0.18), "cloth2": Color(0.24, 0.16, 0.12), "hair": Color(0.18, 0.12, 0.08)}
		"iron_brother": return {"skin": Color(0.40, 0.40, 0.42), "cloth": Color(0.30, 0.30, 0.33), "cloth2": Color(0.18, 0.18, 0.20), "hair": Color(0.22, 0.22, 0.24)}
	return super.figure_palette()


func _draw() -> void:
	super._draw()
	if kind == "cultist" and state == State.WINDUP and not is_dead():
		draw_arc(Vector2(0, -sprite_h * 0.5), 12 + sin(anim_t * 12.0), 0, TAU, 20, Color(0.65, 0.35, 1.0, 0.85), 1.0)


func _draw_body() -> void:
	super._draw_body()
	if kind == "cultist" and state == State.WINDUP:
		# rune circle while casting: hit it with poise damage or Silence to interrupt
		draw_arc(Vector2(0, -radius), radius + 4 + sin(anim_t * 12.0), 0, TAU, 16, Color(0.6, 0.3, 1.0, 0.8), 1.0)
	if kind in ["dragon", "mirror_wraith", "shadow_moth", "moth_swarm", "mirror_clone"]:
		return
	if kind == "iron_brother":
		draw_rect(Rect2(-radius - 2, -radius * 2.2 - 3, radius * 2 + 4, 4), Color(0.2, 0.2, 0.22))


func _draw_weapon(bob: float) -> void:
	if hd:
		return
	var hand := Vector2(facing.x * radius, -radius + bob)
	match kind:
		"ghoul":
			draw_line(hand, hand + facing * 5, Color(0.7, 0.65, 0.55), 1.0)
		"brute", "iron_brother":
			var swing := 0.0
			if state == State.WINDUP:
				swing = -1.2
			elif state == State.ACTIVE:
				swing = 1.0
			var dir := facing.rotated(swing)
			draw_line(hand, hand + dir * radius * 1.6, Color(0.25, 0.22, 0.2), 3.0)
			draw_rect(Rect2(hand + dir * radius * 1.6 - Vector2(3, 3), Vector2(6, 6)), Color(0.4, 0.38, 0.36))
		"cultist":
			draw_line(hand, hand + Vector2(0, -8), Color(0.3, 0.25, 0.2), 1.0)
			draw_circle(hand + Vector2(0, -9), 1.5, Color(0.5, 0.3, 0.9))
