class_name Combatant
extends CharacterBody2D
## Shared body for heroes and enemies: HP, stamina, poise, PF1e conditions,
## and the commit-to-your-swing action state machine (windup -> active -> recovery).

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, DASH, DRINK, DEAD }

var main: Node = null
var display_name := "Combatant"
var team := "enemy"
var radius := 7.0
var color := Color(0.6, 0.6, 0.6)

# PF1e numbers
var max_hp := 10
var hp := 10
var temp_hp := 0
var ac := 12
var flat_ac := 10
var bab := 1
var saves := {"fort": 2, "ref": 2, "will": 2}
var speed := 70.0

# Action-game resources
var max_stamina := 50.0
var stamina := 50.0
var stamina_regen := 32.0
var stamina_delay := 0.0
var poise_max := 25.0
var poise := 25.0
var poise_delay := 0.0

var conditions := {}            # name -> seconds left
var state: State = State.IDLE
var action: Dictionary = {}
var action_timer := 0.0
var aim := Vector2.RIGHT
var facing := Vector2.RIGHT
var move_input := Vector2.ZERO  # set by player input or AI each frame

var dash_timer := 0.0
var dash_dir := Vector2.ZERO
var dash_recover := 0.0
var dash_chain := 0
var dash_chain_timer := 0.0
var parry_timer := 0.0
var blocking := false
var flash := 0.0
var riposte_ready := 0.0
var anim_t := 0.0
var last_attacker: Combatant = null
var knock := Vector2.ZERO
var sprite_id := ""
var sprite: Sprite2D = null
var cur_anim := ""
var anim_clock := 0.0
var sprite_scale := 0.25
var sprite_h := 30.0
var hurt_t := 0.0
var death_dir := "down"
var trail_t := 0.0
var trail_from := 0.0
var trail_to := 0.0
var trail_r := 20.0
var hd := false                 # drawn from DorkTeach's concept art with procedural animation
var hd_pose := ""
var hd_side := 1.0
var hd_dead_t := 0.0
var hd_step := 0


var is_boss := false
var last_flash_ms := 0
var hover := 0.0            # flying bodies float this high above their shadow


var dash_count := 0
var damaged_by := {}         # who has landed blows on us (for kill-steal complaints)


func setup_common() -> void:
	hp = max_hp
	stamina = max_stamina
	poise = poise_max
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius * 0.8
	shape.shape = circle
	shape.name = "Body"
	add_child(shape)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if sprite_id != "" and Art.hd_has(sprite_id):
		hd = true
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite_scale = 0.25
		sprite.scale = Vector2(sprite_scale, sprite_scale)
		var m: Dictionary = Art.hd_pose(sprite_id, "idle")
		sprite_h = float(m["foot"][1]) * sprite_scale * 0.85
		_set_hd_pose("idle")
		add_child(sprite)
	elif sprite_id != "":
		sprite = Sprite2D.new()
		sprite.texture = Art.lit(sprite_id)
		sprite.region_enabled = true
		var fs: Vector2 = Art.frame_size(sprite_id)
		sprite_scale = float(Art.char_meta(sprite_id).get("scale", 0.25))
		sprite.scale = Vector2(sprite_scale, sprite_scale)
		sprite.position = Vector2(0, -(Art.foot_y(sprite_id) - fs.y / 2.0) * sprite_scale)
		sprite_h = fs.y * sprite_scale * 0.62
		sprite.region_rect = Art.frame_rect(sprite_id, "idle_down", 0)
		add_child(sprite)


# ---------- PF1e queries ----------

func is_dead() -> bool:
	return state == State.DEAD


func has(cond: String) -> bool:
	return conditions.get(cond, 0.0) > 0.0


func add_condition(cond: String, seconds: float) -> void:
	conditions[cond] = max(conditions.get(cond, 0.0), seconds)


func is_flat_footed() -> bool:
	# an enemy that hasn't noticed you yet is caught flat-footed (Puck's favourite kind)
	return has("asleep") or has("staggered") or has("prone") or has("parried") or (get("aware") == false)


func get_ac(flat: bool) -> int:
	var v := flat_ac if flat else ac
	if has("raging"):
		v -= 2
	return v


func get_save(kind: String) -> int:
	var v: int = saves.get(kind, 0)
	if kind == "will" and has("raging"):
		v += 2
	if kind == "will" and has("dreamleaf_share"):
		v += 2
	return v


func can_act() -> bool:
	return state != State.DEAD and not has("asleep") and not has("staggered") and not has("prone")


func busy() -> bool:
	return state != State.IDLE


func spend_stamina(amount: float) -> bool:
	if stamina <= 0.0:
		return false
	stamina -= amount
	stamina_delay = 0.6
	return true


# ---------- Actions ----------

## Begins a committed action. Returns false if it can't start.
func start_action(a: Dictionary) -> bool:
	if not can_act() or state != State.IDLE:
		return false
	if has("nauseated") and a.get("is_attack", true):
		return false
	if not spend_stamina(a.get("stamina", 0.0)):
		return false
	action = a
	state = State.WINDUP
	action_timer = a.get("windup", 0.2)
	if a.has("on_start"):
		a["on_start"].call()
	return true


func start_dash(dir: Vector2) -> bool:
	if not can_act() or dash_recover > 0.0:
		return false
	if state != State.IDLE and not (state == State.RECOVERY and action_timer < action.get("recovery", 0.3) * 0.5):
		return false
	if dash_chain >= 2:
		return false
	Sfx.play("dash", global_position, -6.0)
	var cost := (14.0 if not has("haze") else 10.0) * (0.5 if self is Hero and call("prop", "feather") else 1.0)
	if self is Hero and call("prop", "dust"):
		main.spawn_cloud(self, global_position, 20.0, 2.5, "Dreamleaf", 13)
	if not spend_stamina(cost):
		return false
	if dir == Vector2.ZERO:
		dir = facing
	dash_dir = dir.normalized()
	dash_count += 1
	dash_timer = dash_length()
	main.dust(global_position)
	state = State.DASH
	dash_chain += 1
	dash_chain_timer = 0.8
	return true


func dash_length() -> float:
	return 0.25


func start_parry() -> void:
	if not can_act() or state != State.IDLE:
		return
	if parry_timer <= -0.4:  # small cooldown so it can't be spammed
		parry_timer = 0.1
		spend_stamina(6.0)


func interrupt(stagger_time: float = 0.0) -> void:
	if state == State.DEAD:
		return
	if state in [State.WINDUP, State.ACTIVE, State.RECOVERY, State.DRINK]:
		state = State.IDLE
		action = {}
	if stagger_time > 0.0:
		add_condition("staggered", stagger_time)


func _physics_process(delta: float) -> void:
	if main == null:
		return
	anim_t += delta
	flash = max(0.0, flash - delta)
	_tick_conditions(delta)
	if state == State.DEAD:
		velocity = Vector2.ZERO
		queue_redraw()
		return

	# resources
	stamina_delay -= delta
	if stamina_delay <= 0.0 and state != State.DASH:
		var rate := stamina_regen
		if has("sunthistle"):
			rate *= 2.0
		if has("munchies"):
			rate *= 0.5
		stamina = min(max_stamina, stamina + rate * delta)
	poise_delay -= delta
	if poise_delay <= 0.0:
		poise = min(poise_max, poise + poise_max * 0.5 * delta)
	parry_timer -= delta
	riposte_ready = max(0.0, riposte_ready - delta)
	dash_recover = max(0.0, dash_recover - delta)
	dash_chain_timer -= delta
	if dash_chain_timer <= 0.0:
		dash_chain = 0

	_think(delta)

	var vel := Vector2.ZERO
	match state:
		State.IDLE:
			if can_act():
				var mv := move_input
				if has("confused"):
					mv = mv.rotated(sin(anim_t * 3.0) * 2.0)
				mv = main.steer(self, mv)
				vel = mv.limit_length(1.0) * get_speed()
				if blocking:
					vel *= 0.4
				if mv.length() > 0.1 and not blocking:
					facing = mv.normalized()
		State.WINDUP:
			action_timer -= delta
			if not action.get("lock_aim", false):
				facing = aim
			vel = move_input.limit_length(1.0) * get_speed() * action.get("move_mult", 0.15)
			if action_timer <= 0.0:
				state = State.ACTIVE
				action_timer = action.get("active", 0.08)
				_perform()
		State.ACTIVE:
			action_timer -= delta
			vel = facing * action.get("lunge", 0.0)
			if action_timer <= 0.0:
				state = State.RECOVERY
				action_timer = action.get("recovery", 0.3)
		State.RECOVERY:
			action_timer -= delta
			if action_timer <= 0.0:
				state = State.IDLE
				var next = action.get("then", null)
				action = {}
				if next is Dictionary:
					start_action_free(next)
		State.DASH:
			dash_timer -= delta
			vel = dash_dir * (240.0 if not has("raging") else 220.0)
			if dash_timer <= 0.0:
				state = State.IDLE
				dash_recover = 0.2
		State.DRINK:
			action_timer -= delta
			vel = move_input.limit_length(1.0) * get_speed() * 0.3
			if action_timer <= 0.0:
				state = State.IDLE
				_finish_drink()

	velocity = vel + knock
	knock = knock.move_toward(Vector2.ZERO, 600.0 * delta)
	var before := position
	move_and_slide()
	position = main.keep_walkable(before, position, radius)
	hurt_t = max(0.0, hurt_t - delta)
	trail_t = max(0.0, trail_t - delta)
	_update_anim()
	queue_redraw()


func view_dir() -> String:
	var f := aim if state in [State.WINDUP, State.ACTIVE, State.RECOVERY] else facing
	if absf(f.x) > absf(f.y) * 0.9:
		return "side"
	return "up" if f.y < 0.0 else "down"


func _set_hd_pose(pose: String) -> void:
	if pose == hd_pose:
		return
	hd_pose = pose
	var m: Dictionary = Art.hd_pose(sprite_id, pose)
	sprite.texture = Art.lit(m["tex"])


## Concept-art characters: one painted pose per state, brought to life with
## breathing, walk bob, wind-up lean, lunge, flinch and a sideways fall.
func _update_hd() -> void:
	var dt := get_physics_process_delta_time()
	var f := aim if state in [State.WINDUP, State.ACTIVE, State.RECOVERY] else facing
	if absf(f.x) > 0.15:
		hd_side = signf(f.x)
	var pose := "idle"
	var rot := 0.0
	var sx := 1.0
	var sy := 1.0
	var off := Vector2.ZERO
	var moving := velocity.length() > 8.0
	var attacking: bool = action.get("is_attack", true) and not action.get("cast_anim", false)
	match state:
		State.WINDUP, State.ACTIVE, State.RECOVERY:
			var total: float = max(0.01, action.get({State.WINDUP: "windup", State.ACTIVE: "active", State.RECOVERY: "recovery"}[state], 0.2))
			var prog: float = clamp(1.0 - action_timer / total, 0.0, 1.0)
			if attacking:
				match state:
					State.WINDUP:
						pose = "windup" if Art.hd_has_pose(sprite_id, "windup") else ("strike" if Art.hd_has_pose(sprite_id, "strike") else "idle")
						rot = -0.16 * prog
						sx = 1.0 - 0.06 * prog
						sy = 1.0 + 0.04 * prog
						off.x = -2.0 * prog
					State.ACTIVE:
						pose = "strike" if Art.hd_has_pose(sprite_id, "strike") else ("windup" if Art.hd_has_pose(sprite_id, "windup") else "idle")
						if "slam" in str(action.get("name", "")) and Art.hd_has_pose(sprite_id, "slam"):
							pose = "slam"
						rot = 0.2
						sx = 1.1
						sy = 0.94
						off.x = 4.0
					State.RECOVERY:
						pose = "strike" if Art.hd_has_pose(sprite_id, "strike") and prog < 0.5 else "idle"
						var e := 1.0 - prog
						rot = 0.2 * e
						sx = 1.0 + 0.1 * e
						sy = 1.0 - 0.06 * e
						off.x = 4.0 * e
			else:
				# casting: rise up a little and glow
				pose = "cast" if Art.hd_has_pose(sprite_id, "cast") else "idle"
				sy = 1.0 + 0.05 * sin(prog * PI)
				off.y = -2.0 * sin(prog * PI)
		State.DASH:
			if absf(velocity.x) > 5.0:
				hd_side = signf(velocity.x)
			if Art.hd_has_pose(sprite_id, "run0"):
				# a sprint (Puck): two running frames
				pose = "run%d" % (int(anim_t * 12.0) % 2)
			elif Art.hd_has_pose(sprite_id, "dodge"):
				pose = "dodge"
			else:
				sx = 1.18
				sy = 0.9
				rot = 0.12
		State.DRINK:
			if Art.hd_has_pose(sprite_id, "drink"):
				pose = "drink"
		State.DEAD:
			hd_dead_t += dt
			if Art.hd_has_pose(sprite_id, "dead"):
				# painted fall: stagger (or kneel) briefly, then the corpse
				if hd_dead_t < 0.3:
					pose = "fall" if Art.hd_has_pose(sprite_id, "fall") else ("hurt" if Art.hd_has_pose(sprite_id, "hurt") else "idle")
					rot = -0.1 * hd_dead_t / 0.3
				else:
					pose = "dead"
			else:
				var k: float = clamp(hd_dead_t / 0.45, 0.0, 1.0)
				k = 1.0 - pow(1.0 - k, 3.0)
				rot = -1.5 * k
				off.y = 2.0 * k
		_:
			if hurt_t > 0.0 or has("staggered") or has("parried"):
				var h: float = clamp(hurt_t / 0.3, 0.0, 1.0)
				if Art.hd_has_pose(sprite_id, "hurt"):
					pose = "hurt"
					h *= 0.4
				rot = -0.22 * h
				sx = 1.0 + 0.1 * h
				sy = 1.0 - 0.1 * h
				off.x = -3.0 * h
			elif has("asleep") or has("prone"):
				rot = -0.5
			elif moving:
				var n := Art.hd_walk_count(sprite_id)
				var ratio: float = clamp(velocity.length() / max(speed, 1.0), 0.3, 1.5)
				anim_clock += dt * ratio
				var step := sin(anim_clock * 11.0)
				off.y = -absf(step) * 1.6
				var step_i := int(anim_clock * 11.0 / PI)
				if step_i != hd_step and team == "hero":
					hd_step = step_i
					Sfx.play("step", global_position, -9.0 if self == main.leader else -17.0, 0.12)
				if f.y < -0.55 and absf(f.x) < 0.6 and Art.hd_has_pose(sprite_id, "back"):
					pose = "back"
					rot = step * 0.035
					sy = 1.0 + absf(step) * 0.025
				elif n > 1:
					pose = "walk%d" % (int(anim_clock * 6.0) % n)
					rot = step * 0.02
				elif n == 1:
					# one painted stride: swap with the standing pose for a two-beat walk
					pose = "walk0" if fmod(anim_clock * 11.0 / PI, 2.0) < 1.0 else "idle"
					rot = step * 0.03
				else:
					rot = step * 0.05
					sy = 1.0 + absf(step) * 0.03
			else:
				if f.y < -0.55 and absf(f.x) < 0.6 and Art.hd_has_pose(sprite_id, "back"):
					pose = "back"
				var b := sin(anim_t * 2.4)
				sy = 1.0 + 0.015 * b
				sx = 1.0 - 0.008 * b
	if state != State.DEAD:
		hd_dead_t = 0.0
	_set_hd_pose(pose)
	var m: Dictionary = Art.hd_pose(sprite_id, pose)
	var faces := float(m["faces"])
	var flip := hd_side != faces
	sprite.flip_h = flip
	var fx: float = float(m["foot"][0])
	var fy: float = float(m["foot"][1])
	sprite.offset = Vector2(-(float(m["w"]) - fx) if flip else -fx, -fy)
	# rotation and lean are written for a right-facing body: mirror for left
	sprite.rotation = rot * hd_side
	if self is Hero and get("emote_kind") != "" and state == State.IDLE:
		match str(get("emote_kind")):
			"flex":
				var k := 0.5 + 0.5 * sin(anim_t * 7.0)
				sx *= 1.0 + 0.07 * k
				sy *= 1.0 + 0.04 * k
			"pray":
				sy *= 0.9
				off.y += 2.0
				rot += 0.08
			"scribble":
				rot += 0.1 + sin(anim_t * 14.0) * 0.02
			"pipe":
				sy *= 1.0 + 0.015 * sin(anim_t * 2.0)
	if hover > 0.0 and state != State.DEAD:
		off.y -= hover + sin(anim_t * 2.6) * hover * 0.18
	sprite.position = Vector2(off.x * hd_side, off.y)
	sprite.scale = Vector2(sprite_scale * sx, sprite_scale * sy)
	if state == State.DASH:
		sprite.modulate = Color(1.2, 1.2, 1.3, 0.6)
	elif has("asleep"):
		sprite.modulate = Color(0.65, 0.65, 1.0)
	elif has("confused"):
		sprite.modulate = Color(1.2, 0.8, 1.2)
	elif state == State.DEAD:
		sprite.modulate = Color(0.85, 0.8, 0.8) if pose == "dead" else Color(0.75, 0.7, 0.7)
	else:
		sprite.modulate = Color(1, 1, 1)


func _update_anim() -> void:
	if sprite == null:
		return
	if hd:
		_update_hd()
		return
	var dir := view_dir()
	var f := aim if state in [State.WINDUP, State.ACTIVE, State.RECOVERY] else facing
	var anim := "idle_" + dir
	var fixed := -1
	match state:
		State.DEAD:
			anim = "death_" + death_dir
		State.WINDUP, State.ACTIVE, State.RECOVERY:
			if not action.get("is_attack", true) or action.get("cast_anim", false):
				anim = "cast_" + dir
			else:
				anim = "attack_" + dir
				var total: float = max(0.01, action.get({State.WINDUP: "windup", State.ACTIVE: "active", State.RECOVERY: "recovery"}[state], 0.2))
				var prog: float = clamp(1.0 - action_timer / total, 0.0, 0.999)
				match state:
					State.WINDUP: fixed = int(prog * 3.0)
					State.ACTIVE: fixed = 3
					State.RECOVERY: fixed = 4 + int(prog * 2.0)
		State.DASH:
			anim = "walk_" + dir
		State.DRINK:
			anim = "cast_" + dir
		_:
			if hurt_t > 0.0 or has("staggered") or has("parried") or has("asleep") or has("prone"):
				anim = "hurt_" + dir
			elif velocity.length() > 8.0:
				anim = "walk_" + dir
	if state != State.DEAD:
		sprite.flip_h = dir == "side" and f.x < 0.0
	if cur_anim != anim:
		cur_anim = anim
		anim_clock = 0.0
	var spd: float = 1.7 if state == State.DASH else (velocity.length() / max(speed, 1.0) * 1.1 if anim.begins_with("walk") else 1.0)
	anim_clock += get_physics_process_delta_time() * spd
	var count := Art.anim_count(sprite_id, anim)
	var frame := fixed
	if frame < 0:
		frame = int(anim_clock * Art.anim_fps(anim))
		frame = frame % count if Art.anim_loops(anim) else min(frame, count - 1)
	sprite.region_rect = Art.frame_rect(sprite_id, anim, clamp(frame, 0, count - 1))
	if state == State.DASH:
		sprite.modulate = Color(1.2, 1.2, 1.3, 0.6)
	elif has("asleep"):
		sprite.modulate = Color(0.65, 0.65, 1.0)
	elif has("confused"):
		sprite.modulate = Color(1.2, 0.8, 1.2)
	else:
		sprite.modulate = Color(1, 1, 1)


## Follow-up combo hits don't pay the "must be idle" check.
func start_action_free(a: Dictionary) -> void:
	if not can_act():
		return
	if not spend_stamina(a.get("stamina", 0.0)):
		return
	action = a
	state = State.WINDUP
	action_timer = a.get("windup", 0.2)


func get_speed() -> float:
	var s := speed
	if has("munchies"):
		s *= 0.85
	if has("stand"):
		s = 0.0
	if has("slowed"):
		s *= 0.5
	return s


func _tick_conditions(delta: float) -> void:
	for k in conditions.keys():
		conditions[k] -= delta
		if conditions[k] <= 0.0:
			conditions.erase(k)
			_condition_ended(k)


func _condition_ended(_cond: String) -> void:
	pass


func _think(_delta: float) -> void:
	pass


func _finish_drink() -> void:
	pass


## Called when the action becomes active: resolve hits or run the custom effect.
func _perform() -> void:
	if action.get("shape", "") in ["arc", "line"] and not action.has("custom") and action.get("is_attack", true):
		var heavy: bool = action.get("heavy", false) or sprite_id in ["brute", "iron_brother", "average"]
		Sfx.play("swing_heavy" if heavy else "swing", global_position, -4.0 if heavy else -6.0)
	if action.get("shape", "") == "arc" and not action.has("custom"):
		var half: float = deg_to_rad(action.get("arc", 90.0)) / 2.0
		var swing := 1.0 if int(action.get("combo", 0)) % 2 == 0 else -1.0
		trail_from = facing.angle() - half * swing
		trail_to = facing.angle() + half * swing
		trail_r = action.get("reach", 20.0) + 4.0
		trail_t = 0.16
	if action.has("custom"):
		action["custom"].call()
		return
	var targets: Array = main.targets_in_area(self, action)
	var hit_any := false
	for t in targets:
		hit_any = true
		strike(t, action)
	if hit_any:
		main.hitstop(0.05 if action.get("heavy", false) else 0.03)
		if action.get("heavy", false):
			main.shake(3.0)


## One PF1e attack against one target (melee or projectile).
func strike(t: Combatant, a: Dictionary) -> void:
	if t.is_dead():
		return
	var atk: Dictionary = a.get("attack", {}).duplicate()
	var flank: bool = main.is_flanked(t, self)
	var behind := _is_behind(t)
	if flank:
		atk["bonus"] = atk.get("bonus", 0) + 2
	if has("gigglecap"):
		atk["bonus"] = atk.get("bonus", 0) + 1
	if behind:
		atk["force_flat"] = true
	if riposte_ready > 0.0 and a.get("is_attack", true):
		atk["force_flat"] = true
		atk["auto_threat"] = true
		atk["name"] = "RIPOSTE"
		riposte_ready = 0.0
	_modify_attack(t, atk, flank or behind or t.is_flat_footed())
	var res: Dictionary = Rules.resolve_attack(self, t, atk)
	var dmg: int = res["damage"]
	var poise_dmg: float = a.get("poise_dmg", 10.0)
	if res["result"] == "graze":
		poise_dmg *= 0.3
	t.take_hit(self, dmg, poise_dmg, res["result"], (t.global_position - global_position).normalized() * a.get("knockback", 40.0))
	_on_hit_landed(t, res)


func _is_behind(t: Combatant) -> bool:
	var to_me := (global_position - t.global_position).normalized()
	return t.facing.dot(to_me) < -0.5 and t.state == State.IDLE


func _modify_attack(_t: Combatant, _atk: Dictionary, _sneaky: bool) -> void:
	pass


func _on_hit_landed(_t: Combatant, _res: Dictionary) -> void:
	pass


## Apply damage. Handles dash i-frames, parries, blocks, poise and death.
func take_hit(attacker: Combatant, amount: int, poise_dmg: float, result: String, push: Vector2 = Vector2.ZERO) -> bool:
	if state == State.DEAD:
		return false
	if state == State.DASH:
		main.float_text(global_position, "dodge", Color(0.7, 0.7, 0.7))
		return false
	if self is Hero and call("prop", "mirror") and attacker != null and attacker.team != team and randf() < 0.15:
		main.float_text(global_position + Vector2(0, -sprite_h - 6), "a reflection shatters", Color(0.75, 0.9, 1.0))
		Sfx.play("shatter", global_position, -8.0)
		return false
	if parry_timer > 0.0 and attacker != null and attacker.team != team:
		Sfx.play("parry", global_position)
		main.float_text(global_position, "PARRY!", Color(1.0, 0.85, 0.3))
		attacker.interrupt(1.2)
		attacker.add_condition("parried", 1.2)
		riposte_ready = 1.5
		main.hitstop(0.08)
		Rules.logged.emit("%s parries %s" % [display_name, attacker.display_name])
		return false
	if blocking and attacker != null and stamina > 0.0:
		Sfx.play("block", global_position, -2.0)
		spend_stamina(amount * 2.0)
		amount = int(ceil(amount * 0.4))
		poise_dmg *= 0.3
	if has("ward"):
		amount = int(ceil(amount * 0.5))
	if has("asleep"):
		conditions.erase("asleep")
		main.float_text(global_position + Vector2(0, -14), "wakes!", Color(0.7, 0.7, 1.0))
	last_attacker = attacker
	if attacker != null:
		damaged_by[attacker] = true
	var absorbed: int = min(temp_hp, amount)
	temp_hp -= absorbed
	amount -= absorbed
	hp -= amount
	flash = 0.12
	hurt_t = 0.3
	if result == "crit":
		Sfx.play("hit_crit", global_position)
	else:
		Sfx.play("hit", global_position, -9.0 if result == "graze" else -3.0)
	if team == "hero":
		Sfx.play("hurt", global_position, -6.0)
	var light := team != "hero" and poise_max <= 20.0
	knock = push * ((1.8 if light else 0.6) if poise > poise_dmg else 2.0)
	# visible reaction: white flash (shader, survives night tint), flinch, shake
	# big bodies get hit constantly: a short, softer flash at most every 0.4 s, or they'd glow white
	if Settings.hit_flash and (not is_boss or Time.get_ticks_msec() - last_flash_ms > 400):
		last_flash_ms = Time.get_ticks_msec()
		var fc := Color(2.6, 2.4, 2.3) if team != "hero" else Color(2.6, 0.6, 0.5)
		JuiceLite.flash(sprite, fc.lerp(Color(1.4, 1.35, 1.3), 0.6) if is_boss else fc, 0.08 if is_boss else 0.16)
	if light and result != "graze" and state == State.WINDUP:
		interrupt(0.25)
	var involves_leader: bool = (attacker != null and attacker == main.leader) or self == main.leader
	if involves_leader:
		main.hit_shake(0.45 if result == "crit" else (0.15 if result == "graze" else 0.28))
		if result == "crit":
			main.hitstop(0.07)
	var col := Color(0.95, 0.9, 0.85)
	var txt := str(amount + absorbed)
	if result == "crit":
		col = Color(1.0, 0.8, 0.2)
		txt = "CRIT " + txt
	elif result == "graze":
		col = Color(0.55, 0.55, 0.55)
		txt = "graze " + txt
	if team == "hero":
		col = col.lerp(Color(1.0, 0.3, 0.3), 0.6)
	main.float_text(global_position + Vector2(0, -radius - 6), txt, col)
	main.blood(global_position, 3 if result == "graze" else 8)
	main.spark(global_position + Vector2(0, -sprite_h * 0.5), result, push)
	poise -= poise_dmg
	poise_delay = 2.0
	if poise <= 0.0:
		poise = poise_max
		interrupt(0.9)
		main.float_text(global_position + Vector2(0, -radius - 14), "staggered", Color(0.9, 0.6, 0.3))
	if hp <= 0 and not _cheat_death():
		die()
	_after_hit(attacker, amount + absorbed)
	return true


func _cheat_death() -> bool:
	return false


func _after_hit(_attacker: Combatant, _amount: int) -> void:
	pass


func heal(amount: int) -> void:
	if state == State.DEAD:
		return
	hp = min(max_hp, hp + amount)
	main.float_text(global_position + Vector2(0, -radius - 6), "+%d" % amount, Color(0.5, 1.0, 0.6))


func die() -> void:
	Sfx.play("death", global_position, -2.0, 0.12)
	hp = 0
	death_dir = view_dir()
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	action = {}
	conditions.clear()
	main.blood(global_position, 24)
	main.on_death(self)
	z_index = -1


# ---------- Drawing (placeholder grimdark pixel shapes) ----------

func _draw() -> void:
	# shadow
	_ellipse(Vector2(0, 0), Vector2(radius * 1.2, radius * 0.45), Color(0, 0, 0, 0.45))
	if state == State.DEAD:
		if sprite == null:
			_draw_corpse()
		return
	_draw_telegraph()
	if trail_t > 0.0:
		_draw_trail()
	if sprite == null:
		_draw_body()
		if flash > 0.0:
			draw_rect(Rect2(-radius, -radius * 2.4, radius * 2, radius * 2.4), Color(1, 1, 1, 0.55))
	_draw_status()


func _draw_trail() -> void:
	var k := trail_t / 0.16
	var c := Vector2(0, -sprite_h * 0.45)
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var a: float = lerp(trail_from, trail_to, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a) * 0.75) * trail_r)
		inner.append(c + Vector2(cos(a), sin(a) * 0.75) * trail_r * (0.55 + 0.25 * float(i) / n))
	inner.reverse()
	var poly := pts + inner
	var col := Color(1.0, 0.95, 0.85, 0.55 * k) if team == "hero" else Color(1.0, 0.4, 0.3, 0.5 * k)
	draw_colored_polygon(poly, col)
	draw_polyline(pts, Color(1, 1, 1, 0.8 * k), 1.0)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _draw_corpse() -> void:
	draw_rect(Rect2(-radius, -2, radius * 2, 4), color.darkened(0.6))
	draw_rect(Rect2(-radius * 0.6, -3, radius * 0.8, 2), Color(0.35, 0.02, 0.02))


## Palette for the little pixel figure: skin, cloth, cloth2 (legs/trim), hair.
func figure_palette() -> Dictionary:
	return {"skin": Color(0.6, 0.5, 0.42), "cloth": color, "cloth2": color.darkened(0.35), "hair": Color(0.2, 0.15, 0.1)}


func _draw_body() -> void:
	var pal := figure_palette()
	var r := radius
	var walking := velocity.length() > 5.0
	var step := sin(anim_t * 12.0) if walking else 0.0
	var bob := absf(step) * -1.0
	var ink := Color(0.03, 0.02, 0.02)
	var hw := r * 0.75                     # half torso width
	var leg_h := r * 0.7
	var torso_h := r * 1.0
	var head := r * 0.75
	var y_legs := -leg_h
	var y_torso := y_legs - torso_h + bob
	var y_head := y_torso - head + 1
	# outline pass
	draw_rect(Rect2(-hw - 1, y_head - 1, hw * 2 + 2, -y_head + 1), ink)
	# legs
	draw_rect(Rect2(-hw * 0.8, y_legs + step, hw * 0.7, leg_h - step), pal["cloth2"])
	draw_rect(Rect2(hw * 0.1, y_legs - step, hw * 0.7, leg_h + step), pal["cloth2"])
	# torso with a light edge on the lit side
	draw_rect(Rect2(-hw, y_torso, hw * 2, torso_h), pal["cloth"])
	draw_rect(Rect2(-hw, y_torso, 1, torso_h), pal["cloth"].lightened(0.25))
	draw_rect(Rect2(-hw, y_torso + torso_h - 2, hw * 2, 1), pal["cloth2"])
	# arms
	draw_rect(Rect2(-hw - 1, y_torso + 1 - step * 0.5, 1, torso_h * 0.7), pal["skin"].darkened(0.2))
	draw_rect(Rect2(hw, y_torso + 1 + step * 0.5, 1, torso_h * 0.7), pal["skin"].darkened(0.2))
	# head
	draw_rect(Rect2(-head * 0.6, y_head, head * 1.2, head), pal["skin"])
	draw_rect(Rect2(-head * 0.6, y_head, head * 1.2, 2), pal["hair"])
	if facing.y > -0.5:
		var ex := facing.x * head * 0.25
		draw_rect(Rect2(ex - 2, y_head + head * 0.5, 1, 1), ink)
		draw_rect(Rect2(ex + 1, y_head + head * 0.5, 1, 1), ink)
	else:
		draw_rect(Rect2(-head * 0.6, y_head, head * 1.2, head), pal["hair"])
	_draw_weapon(bob)


func _draw_weapon(_bob: float) -> void:
	pass


## Red Hades-style danger area while winding up (enemies only).
func _draw_telegraph() -> void:
	if team != "enemy" or state != State.WINDUP or not action.get("telegraph", true):
		return
	var total: float = action.get("windup", 0.5)
	var p: float = clamp(1.0 - action_timer / total, 0.0, 1.0)
	var col := Color(0.85, 0.08, 0.05, 0.18 + 0.2 * p)
	var edge := Color(0.95, 0.15, 0.1, 0.7)
	match action.get("shape", "arc"):
		"arc":
			var reach: float = action.get("reach", 20.0) + 6.0
			var half: float = deg_to_rad(action.get("arc", 90.0)) / 2.0
			var ang := facing.angle()
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				var a := ang - half + 2.0 * half * i / 12.0
				pts.append(Vector2(cos(a), sin(a)) * reach)
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.12))
			var inner := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				var a := ang - half + 2.0 * half * i / 12.0
				inner.append(Vector2(cos(a), sin(a)) * reach * p)
			draw_colored_polygon(inner, col)
			draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), edge, 1.0)
		"circle":
			var c: Vector2 = action.get("_point", global_position) - global_position
			var r: float = action.get("radius", 30.0)
			draw_arc(c, r, 0, TAU, 32, edge, 1.0)
			draw_circle(c, r * p, col)
		"line":
			var l: float = action.get("reach", 120.0)
			var w: float = action.get("width", 6.0)
			var n := facing.orthogonal() * w
			var pts2 := PackedVector2Array([n, facing * l + n, facing * l - n, -n])
			draw_colored_polygon(pts2, Color(col.r, col.g, col.b, 0.1 + 0.2 * p))
			draw_polyline(pts2 + PackedVector2Array([n]), edge, 1.0)


func _draw_status() -> void:
	var y := -sprite_h - 4.0 if sprite != null else -radius * 2.2 - 6
	if team == "enemy" or hp < max_hp:
		var w := radius * 2.4
		draw_rect(Rect2(-w / 2, y, w, 2), Color(0.1, 0.0, 0.0))
		draw_rect(Rect2(-w / 2, y, w * float(hp) / max_hp, 2), Color(0.7, 0.05, 0.05))
	var icons := ""
	if has("asleep"):
		icons += "z"
	if has("confused"):
		icons += "?"
	if has("staggered") or has("parried"):
		icons += "*"
	if has("nauseated"):
		icons += "~"
	if icons != "":
		draw_string(ThemeDB.fallback_font, Vector2(-4, y - 2), icons, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 1.0))
