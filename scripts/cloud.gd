extends Node2D
## Lingering area effects: Puck's herb smoke and Eowilas's Silence dome.

var main: Node
var caster: Combatant
var radius := 28.0
var duration := 4.0
var kind := "Dreamleaf"
var dc := 14
var age := 0.0
var tick := 0.0
var tried := {}


var fuse := 0.0         # Ember: seconds of warning before it lands
var landed := false


func _physics_process(delta: float) -> void:
	age += delta
	tick -= delta
	if age >= duration:
		queue_free()
		return
	queue_redraw()
	if kind in ["Dust", "Fire", "Ember"]:
		_hostile_tick()
		return
	if kind == "Silence":
		for e in main.enemies:
			if e.is_dead() or e.global_position.distance_to(global_position) > radius:
				continue
			e.add_condition("silenced", 0.3)
			if e.state == Combatant.State.WINDUP and e.action.get("is_spell", false):
				e.interrupt(0.6)
				main.float_text(e.global_position + Vector2(0, -16), "silenced!", Color(0.7, 0.7, 0.9))
	elif tick <= 0.0:
		tick = 1.0
		for e in main.enemies:
			if e.is_dead() or e.global_position.distance_to(global_position) > radius + e.radius:
				continue
			var n: int = tried.get(e, 0)
			if n >= 2:
				continue  # each enemy gets at most two saves per cloud
			tried[e] = n + 1
			match kind:
				"Dreamleaf":
					if not e.has("asleep") and not Rules.save(e, "will", dc, "Dreamleaf smoke"):
						e.add_condition("asleep", 5.0)
						e.interrupt(0.0)
						if caster is Hero:
							caster.nana_praise()
				"Gigglecap":
					if not e.has("confused") and not Rules.save(e, "will", dc, "Gigglecap smoke"):
						e.add_condition("confused", 5.0)
						e.target = null
				"Sunthistle":
					if not e.has("nauseated") and not Rules.save(e, "fort", dc, "Sunthistle smoke"):
						e.add_condition("nauseated", 3.0)
						e.interrupt(0.0)
	queue_redraw()


## Boss hazards: they hurt heroes (and anyone not on the caster's team).
func _hostile_tick() -> void:
	if kind == "Ember":
		if landed or age < fuse:
			if landed and tick <= 0.0:
				tick = 1.0
				_burn(1, 4, "ref")
			return
		landed = true
		tick = 1.0
		Sfx.play("slam", global_position, -4.0)
		main.fx_sprite("crater", global_position, radius * 2.6, 1.6, {"ground": true, "grow": 0.15, "hold": 0.5, "tint": Color(1.0, 0.55, 0.3)})
		main.shake(2.5)
		_burn(3, 6, "ref", true)
		return
	if tick > 0.0:
		return
	tick = 1.0
	if kind == "Fire":
		_burn(1, 6, "ref")
	else:
		for h in main.heroes:
			if h.is_dead() or h.global_position.distance_to(global_position) > radius + h.radius:
				continue
			h.take_hit(caster, Rules.roll(1, 4), 4.0, "hit")
			if not h.has("nauseated") and not Rules.save(h, "fort", dc, "moth dust"):
				h.add_condition("nauseated", 2.5)


func _burn(n: int, s: int, save: String, big := false) -> void:
	for h in main.heroes:
		if h.is_dead() or h.global_position.distance_to(global_position) > radius + h.radius:
			continue
		var dmg := Rules.roll(n, s)
		if Rules.save(h, save, dc, "flames"):
			dmg = dmg / 2
		if dmg > 0:
			h.take_hit(caster, dmg, 20.0 if big else 3.0, "hit", (h.global_position - global_position).normalized() * (90.0 if big else 0.0))


func _draw() -> void:
	if kind == "Ember" and not landed:
		var p: float = clamp(age / max(0.01, fuse), 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1.0, 0.35, 0.1, 0.75), 1.0)
		draw_circle(Vector2.ZERO, radius * p, Color(0.95, 0.25, 0.05, 0.18 + 0.22 * p))
		# the falling ember
		draw_circle(Vector2(0, -160.0 * (1.0 - p)), 2.5, Color(1.0, 0.7, 0.3, 0.9))
		return
	if kind in ["Fire", "Ember"]:
		var fade2: float = clamp((duration - age) / 0.6, 0.0, 1.0)
		for i in 7:
			var a := i * 2.4 + age * 0.9
			var rr := radius * (0.2 + 0.65 * fmod(i * 0.37, 1.0))
			var fl := 0.6 + 0.4 * sin(age * 9.0 + i * 1.7)
			draw_circle(Vector2(cos(a), sin(a) * 0.55) * rr, (4.0 + 2.0 * fl), Color(1.0, 0.45 + 0.25 * fl, 0.1, 0.35 * fade2))
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.3, 0.05, 0.08 * fade2))
		return
	if kind == "Dust":
		var fade3: float = clamp(1.0 - (age - duration + 0.6) / 0.6, 0.0, 1.0) * clamp(age / 0.35, 0.0, 1.0)
		var tex3 := Art.fx("smoke_purple")
		if tex3 != null:
			for i in 3:
				var a := i * 2.1 + age * 0.4
				var off := Vector2(cos(a), sin(a) * 0.6) * radius * 0.35
				var sc := radius * (1.3 - i * 0.2) / tex3.get_size().x
				draw_set_transform(off, sin(age * 0.3 + i) * 0.3, Vector2(sc, sc * 0.8))
				draw_texture(tex3, -tex3.get_size() / 2.0, Color(0.35, 0.3, 0.45, 0.6 * fade3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 10:
			var a := i * 1.9 + age * (1.5 + i * 0.1)
			draw_circle(Vector2(cos(a), sin(a) * 0.6) * radius * (0.3 + fmod(i * 0.29, 0.7)), 1.0, Color(0.85, 0.8, 1.0, 0.7 * fade3))
		return
	var fade: float = clamp(1.0 - (age - duration + 0.6) / 0.6, 0.0, 1.0) * clamp(age / 0.35, 0.0, 1.0)
	var painted := Art.fx("rune_ring" if kind == "Silence" else "smoke_purple")
	if painted != null:
		if kind == "Silence":
			var t := Art.fx("rune_ring")
			var k := radius * 2.2 / t.get_size().x
			draw_circle(Vector2.ZERO, radius, Color(0.02, 0.02, 0.05, 0.35 * fade))
			draw_set_transform(Vector2(0, -radius * 0.25), 0.0, Vector2(k, k))
			draw_texture(t, -t.get_size() / 2.0, Color(1, 1, 1, 0.85 * fade))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		var tex := Art.fx("smoke_purple" if kind == "Dreamleaf" else "smoke_green")
		var tint: Color = {"Dreamleaf": Color(1, 1, 1), "Gigglecap": Color(1.2, 0.75, 1.0), "Sunthistle": Color(1, 1, 0.8)}.get(kind, Color.WHITE)
		for i in 3:
			var a := i * 2.1 + age * 0.25
			var off := Vector2(cos(a), sin(a) * 0.6) * radius * 0.35
			var sc := radius * (1.3 - i * 0.2) / tex.get_size().x * (1.0 + 0.05 * sin(age * 1.5 + i))
			draw_set_transform(off, sin(age * 0.3 + i) * 0.3, Vector2(sc, sc * 0.8))
			draw_texture(tex, -tex.get_size() / 2.0, Color(tint.r, tint.g, tint.b, 0.45 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if kind == "Silence":
		draw_circle(Vector2.ZERO, radius, Color(0.02, 0.02, 0.05, 0.45 * fade))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(0.8, 0.8, 1.0, 0.6 * fade), 1.0)
		for i in 6:
			var a := age * 0.6 + i * TAU / 6.0
			draw_circle(Vector2.from_angle(a) * (radius - 4.0), 1.0, Color(0.9, 0.9, 1.0, 0.7 * fade))
		return
	var col: Color = {"Dreamleaf": Color(0.55, 0.5, 0.85), "Gigglecap": Color(0.85, 0.5, 0.7), "Sunthistle": Color(0.75, 0.75, 0.35)}.get(kind, Color.WHITE)
	for i in 9:
		var a := i * 2.4 + age * 0.4
		var r := radius * (0.3 + 0.6 * fmod(i * 0.37, 1.0))
		draw_circle(Vector2(cos(a), sin(a) * 0.6) * r, 7.0 + sin(age * 2.0 + i) * 2.0, Color(col.r, col.g, col.b, 0.22 * fade))
