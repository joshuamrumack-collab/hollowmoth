extends Node2D
## Hollowmoth - Act I slice: "The Hollowmarch Outskirts".
## A hand-built bog zone (artgen/level.py) with a Moth Shrine camp, three
## encounter areas that seal shut, a shortcut gate and the Iron Brother's pit.
## Souls loop: rest = heal + respawn, death = drop Starlight as a moth.

const COMMANDS := ["free", "attack_target", "hold", "fall_back"]
const COMMAND_NAMES := {"free": "Free fight", "attack_target": "Attack my target", "hold": "Hold position", "fall_back": "Fall back"}
const HERO_IDS := ["average", "puck", "brokk", "sael"]
const NIGHT := Color(0.36, 0.37, 0.46)
const GROUND_PROPS := ["grass_0", "grass_1", "grass_2", "grass_3", "mushrooms_0", "mushrooms_1", "fern", "reeds", "bones"]

var heroes: Array = []
var enemies: Array = []
var leader: Hero = null
var command := "free"
var focus_target: Combatant = null
var draughts := 5
var draught_max := 5             # Old Wick sells a longer flask belt
var camp: Node                   # the camp followers (scripts/camp.gd)
var starlight := 0

# Tactics presets (from the design doc)
var tactics_rage := true
var tactics_herbs := true
var tactics_heal := 45
var tactics_draughts := true

# Level
var L: Dictionary = {}
var areas: Array = []            # [{id, name, pos:Vector2, r, encounter, boss}]
var area_state := {}             # id -> "idle" | "active" | "cleared"
var area_enemies := {}           # id -> Array of Enemy
var active_area := ""
var banter: Node = null
var lowhp_said: Dictionary = {}
var paths: Array = []            # [{a, b, hw}]
var solids: Array = []           # [{pos, r}]
var seal_blockers: Array = []    # [{pos, r, node}]
var gate_open := false
var gate_node: Sprite2D
var shrine_pos := Vector2.ZERO
var bounds := Rect2()
var trail: Array = []
var moth_drop: Dictionary = {}   # {pos, amount, node}
var loot_bags: Array = []        # [{pos, item, node}]
var boss_dead := false          # the act's final boss
var bosses_dead := {}            # area id -> true
var rift_pos := Vector2(-9999, -9999)
var night_col := NIGHT
var ending := false              # the Act II finale played: credits lead back to a fresh title
var rift_pending := false
var embers: Array = []
var enemy_shots: Array = []
var feat_offer: Array = []       # feats on offer after the leader levels up (pick one)
const Feats = preload("res://scripts/feats.gd")
var kills_by := {}               # hero id -> kills this act (Brokk keeps count)
var combat_music := false
var started := false
var test_level := false          # playing a hand-drawn test level (tools/maps): no saving             # a game is under way (so quitting saves it)
var bag: Array = []              # loot waiting in the party's bag (see inventory.gd)
var inv: Node = null
const BAG_SIZE := 24

# UI state
var ui := "title"                # title | select | play | level | inventory | dead
var select_i := 0
var areas_ever_cleared := {}
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var banner_col := Color(0.9, 0.85, 0.7)
var dead_t := 0.0
var lightning_t := 18.0
var flash_t := 0.0
var switch_cd := 0.0
var shake_amt := 0.0
var hitstop_active := false
var log_lines: Array = []
var decals: Array = []
var using_mouse := true
var autotest := false
var test_t := 0.0
var route_i := 0
var kills := 0
var deaths := 0
var test_flags := {}

var world: Node2D
var ground_layer: Node2D
var actors: Node2D
var fx: Node2D
var decal_node: Node2D
var camera: Camera2D
var hud: Control
var tint: CanvasModulate
var light_tex: GradientTexture2D
var flicker_lights: Array = []
var tall_props: Array = []       # trees and big props that fade when a hero is behind them
var rain: CPUParticles2D


func _ready() -> void:
	banter = preload("res://scripts/banter.gd").new()
	banter.main = self
	add_child(banter)
	Sfx.music("explore", 2.5)
	Sfx.ambience(true, Art.level.get("weather", "rain" if Run.act == 1 else "ash") == "rain")
	autotest = "--autotest" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--act=") and Run.carry.is_empty():
			Run.act = int(arg.substr(6))
	Art.load_level(Run.act)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			Art.level = Art._load_json("res://assets/level_%s.json" % arg.substr(8))
			test_level = true
	if Run.level_override != "":
		Art.level = Art._load_json("res://assets/level_%s.json" % Run.level_override)
		test_level = true
	banter.talk_done.connect(_on_talk_done)
	inv = preload("res://scripts/inventory.gd").new()
	inv.main = self
	add_child(inv)
	camp = preload("res://scripts/camp.gd").new()
	camp.main = self
	add_child(camp)
	_setup_input()
	Rules.logged.connect(_on_log)
	L = Art.level
	bounds = Rect2(Vector2.ZERO, Vector2(L["size"][0], L["size"][1]))
	shrine_pos = _v(L["shrine"])
	for a in L["areas"]:
		areas.append({"id": a["id"], "name": a["name"], "pos": _v(a["pos"]), "r": float(a["r"]),
			"encounter": a["encounter"], "boss": a.get("boss", false), "final": a.get("final", a.get("boss", false) and not L.has("act")),
			"bossinfo": a.get("bossinfo", {}), "seal": a.get("seal", false)})
		area_state[a["id"]] = "cleared" if a["encounter"].is_empty() else "idle"
		area_enemies[a["id"]] = []
	for p in L["paths"]:
		paths.append({"a": _v(p["a"]), "b": _v(p["b"]), "hw": float(p["hw"])})
	for so in L["solids"]:
		solids.append({"pos": _v(so["pos"]), "r": float(so["r"])})

	var grad_l := Gradient.new()
	grad_l.set_color(0, Color(1, 1, 1, 1))
	grad_l.set_color(1, Color(1, 1, 1, 0))
	light_tex = GradientTexture2D.new()
	light_tex.gradient = grad_l
	light_tex.fill = GradientTexture2D.FILL_RADIAL
	light_tex.fill_from = Vector2(0.5, 0.5)
	light_tex.fill_to = Vector2(1.0, 0.5)
	light_tex.width = 128
	light_tex.height = 128

	process_mode = Node.PROCESS_MODE_ALWAYS
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var ground := Sprite2D.new()
	if L.has("walkmask"):
		# exported builds only carry the imported texture, not the PNG on disk
		var wpath := "res://assets/%s.png" % L["walkmask"]
		if ResourceLoader.exists(wpath):
			var wt: Texture2D = load(wpath)
			walk_img = wt.get_image() if wt != null else null
		if walk_img == null or walk_img.is_empty():
			walk_img = Image.load_from_file(ProjectSettings.globalize_path(wpath))
		if walk_img != null and walk_img.is_compressed():
			walk_img.decompress()
		walk_scale = float(L.get("walkmask_scale", 1.0))
	var gname: String = L.get("ground", "ground")
	ground.texture = Art.lit(gname, gname + "_s", 0.7, Color(0.45, 0.42, 0.38))
	if L.has("night"):
		night_col = Color(L["night"][0], L["night"][1], L["night"][2])
	ground.centered = false
	ground.scale = Vector2(L["tex"], L["tex"])
	world.add_child(ground)
	# where you can walk: shadow beyond the edge and a faint lip along it (tools/artgen/edge_overlay.py)
	if L.has("edge_overlay"):
		var et: Texture2D = Art.tex(L["edge_overlay"])
		if et != null:
			var edge := Sprite2D.new()
			edge.texture = et
			edge.centered = false
			edge.scale = Vector2(L.get("edge_scale", 2.0), L.get("edge_scale", 2.0))
			edge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var em := CanvasItemMaterial.new()
			em.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			edge.material = em
			world.add_child(edge)
	ground_layer = Node2D.new()
	world.add_child(ground_layer)
	decal_node = Node2D.new()
	decal_node.draw.connect(_draw_decals)
	world.add_child(decal_node)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	world.add_child(actors)
	var fx_layer := CanvasLayer.new()
	fx_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	fx_layer.layer = 2
	fx_layer.follow_viewport_enabled = true
	add_child(fx_layer)
	fx = Node2D.new()
	fx_layer.add_child(fx)

	_build_props()
	camp.build()
	_build_atmosphere()

	for i in HERO_IDS.size():
		var h := Hero.new()
		h.main = self
		h.setup(HERO_IDS[i])
		h.position = shrine_pos + Vector2(-24 + i * 16, 50)
		actors.add_child(h)
		heroes.append(h)
		var hl := _make_light(Color(1.0, 0.8, 0.55), 0.28, 0.9, 14.0)
		hl.position = Vector2(0, -10)
		h.add_child(hl)
	var pick := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="):
			pick = max(0, HERO_IDS.find(arg.substr(7)))
	var carried: String = Run.apply(self)
	if carried != "":
		pick = HERO_IDS.find(carried)
	elif Run.act > 1:
		# started straight into a later act (debug/test): bring the party up to strength
		for h in heroes:
			while h.level < 3 + Run.act * 2:
				h.level_up()
	set_leader(heroes[pick])

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(bounds.size.x)
	camera.limit_bottom = int(bounds.size.y)
	add_child(camera)
	camera.make_current()
	camera.global_position = leader.global_position

	tint = CanvasModulate.new()
	tint.color = night_col
	add_child(tint)

	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 5
	add_child(vignette_layer)
	var vig := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.9))
	grad.add_point(0.5, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 128
	gt.height = 72
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_layer.add_child(vig)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	hud_layer.add_child(hud)

	_on_log("The stars are going out. Begin at the Moth Shrine.")
	if autotest:
		ui = "play"
		for h in heroes:
			h.controlled = false
		print("AUTOTEST start act %d" % Run.act)
	elif Run.resume:
		_apply_world(Run.world)
		Run.resume = false
		call_deferred("_begin_resume")
	elif Run.level_override != "":
		call_deferred("set_ui", "select")
	elif Run.act > 1:
		call_deferred("_begin_act")


## Hand-drawn test levels in assets (level_<name>.json with a walk mask), for the title screen.
func _test_levels() -> Array:
	var out := []
	if not OS.is_debug_build():
		return out
	for f in DirAccess.get_files_at("res://assets"):
		if f.begins_with("level_") and f.ends_with(".json"):
			var n := f.trim_prefix("level_").trim_suffix(".json")
			if not n.is_valid_int() and n != "roundtrip":
				out.append("Try: " + n)
	return out


## A loaded save: bosses stay dead, the shortcut stays open, the party wakes at the shrine.
func _apply_world(w: Dictionary) -> void:
	for id in w.get("bosses_dead", []):
		bosses_dead[id] = true
		area_state[id] = "cleared"
		for a in areas:
			if a["id"] == id and a["final"]:
				boss_dead = true
	for id in w.get("cleared", []):
		areas_ever_cleared[id] = true
	if w.get("gate_open", false):
		gate_open = true
		gate_node.texture = Art.prop_lit("gate_open")
	draughts = int(w.get("draughts", draught_max))
	var m: Dictionary = w.get("moth", {})
	if not m.is_empty():
		_spawn_moth(Vector2(m["pos"][0], m["pos"][1]), int(m["amount"]))


func _begin_resume() -> void:
	set_ui("play")
	Sfx.play("shrine", null, -4.0, 0.0)
	show_banner(L.get("subtitle", Run.ACT_NAMES[clamp(Run.act, 1, Run.LAST_ACT)]).to_upper(), "You wake at the Moth Shrine", Color(0.75, 0.8, 1.0), 3.0)


func save_now() -> void:
	if started and not autotest and ui != "dead":
		Run.save_game(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


## A later act starts in play: no title or hero select, just the act card and a scene.
func _begin_act() -> void:
	set_ui("play")
	show_banner(L.get("title", "ACT %d" % Run.act), "Beyond the rift", Color(0.95, 0.6, 0.35) if Run.act == 2 else Color(0.7, 0.85, 1.0), 4.0)
	banter.talk("act%d_intro" % Run.act)


func _on_talk_done(cue: String) -> void:
	if cue.begins_with("npc_"):
		camp.open_shop(cue.substr(4))
	elif cue.begins_with("rift_enter") and rift_pending:
		Run.goto_act(Run.act + 1, self)
	elif ending and cue == L["areas"].filter(func(a): return a.get("final", false))[0].get("bossinfo", {}).get("dead", ""):
		banter.talk("ending", false)
	elif ending and cue == "ending":
		menu_back = "title"
		set_ui("credits")


static func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


# =====================================================================
# World building
# =====================================================================

func _build_props() -> void:
	for p in L["props"]:
		var name: String = p["name"]
		var pos := _v(p["pos"])
		match name:
			"campfire":
				var cook: Texture2D = Art.prop("station_cookfire")
				if cook != null:
					# DorkTeach's camp fire: bench, cauldron and the flames
					var cf := Sprite2D.new()
					cf.texture = cook
					cf.scale = Vector2(0.25, 0.25)
					cf.offset = Vector2(0, -cook.get_height() / 2.0 + 20.0)
					cf.position = pos
					actors.add_child(cf)
					solids.append({"pos": pos, "r": 14.0})
				else:
					var fire := AnimatedSprite2D.new()
					fire.sprite_frames = Art.prop_frames("campfire", 4, 9.0)
					fire.scale = Vector2(0.25, 0.25)
					fire.offset = Vector2(0, -40)
					fire.position = pos
					fire.play("default")
					actors.add_child(fire)
				var l := _make_light(Color(1.0, 0.55, 0.25), 1.15, 3.4, 40.0)
				l.position = pos + Vector2(0, -10)
				world.add_child(l)
				flicker_lights.append(l)
				_embers(pos + Vector2(0, -12), 18)
				Sfx.fire_at(world, pos, -2.0)
			"torch", "brazier":
				var t := AnimatedSprite2D.new()
				t.sprite_frames = Art.prop_frames(name, 3, 10.0)
				var th: float = Art.manifest["props"][name + "_0"]["h"]
				var h: float = th * 0.25
				t.scale = Vector2(0.25, 0.25)
				t.offset = Vector2(0, -th / 2.0 + 4)
				t.position = pos
				t.play("default")
				t.frame = randi() % 3
				actors.add_child(t)
				var l2 := _make_light(Color(1.0, 0.6, 0.3), 0.8 if name == "torch" else 0.9, 2.0 if name == "torch" else 2.5, 30.0)
				l2.position = pos + Vector2(0, -h + 4)
				world.add_child(l2)
				flicker_lights.append(l2)
				if name == "brazier":
					_embers(pos + Vector2(0, -h + 4), 6)
					Sfx.fire_at(world, pos, -8.0)
			_:
				var sp := Sprite2D.new()
				sp.texture = Art.prop_lit(name)
				var sz: Vector2 = Art.prop(name).get_size()
				var sc := Art.prop_scale(name)
				sp.scale = Vector2(sc, sc)
				sp.offset = Vector2(0, -sz.y / 2.0 + 2.0 / sc)
				sp.position = pos
				if name.begins_with("pine") or name.begins_with("dead_tree"):
					sp.flip_h = (int(pos.x) % 2) == 0
				if L.has("prop_tint") and name != "moth_shrine":
					sp.modulate = Color(L["prop_tint"][0], L["prop_tint"][1], L["prop_tint"][2])
				if name in GROUND_PROPS:
					ground_layer.add_child(sp)
				else:
					actors.add_child(sp)
					if name.begins_with("pine") or name.begins_with("dead_tree") or name.begins_with("ruin") or name == "gibbet":
						tall_props.append(sp)
				if name == "moth_shrine":
					var ml := _make_light(Color(0.55, 0.65, 1.0), 1.1, 1.8, 30.0)
					ml.position = pos + Vector2(0, -20)
					world.add_child(ml)
	# lava and ember floors light themselves (written by the Tiled importer)
	for gl in L.get("glows", []):
		var gll: PointLight2D
		match str(gl[2]):
			"lava": gll = _make_light(Color(1.0, 0.45, 0.15), 0.9, 3.2, 10.0)
			"water": gll = _make_light(Color(0.45, 0.6, 0.95), 0.45, 4.0, 40.0)   # moonlight on the water
			_: gll = _make_light(Color(1.0, 0.5, 0.2), 0.7, 4.0, 10.0)
		gll.position = Vector2(gl[0], gl[1])
		world.add_child(gll)
	# the rift (DorkTeach's concept art): the way on to the next act
	if Art.manifest["props"].has("rift"):
		var pit: Dictionary = {}
		for a in L["areas"]:
			if a.get("final", a.get("boss", false)) and Run.act == 1 and not L.has("exit"):
				pit = a
		var spots: Array = []
		if L.has("exit") and Run.act < Run.LAST_ACT:
			spots.append([_v(L["exit"]), true])
		elif not pit.is_empty():
			spots.append([_v(pit["pos"]) + Vector2(0, -float(pit["r"]) * 0.82), true])
		if L.has("rift"):
			spots.append([_v(L["rift"]), false])   # where the party came through: decoration
		for sp_ in spots:
			var rp: Vector2 = sp_[0]
			if sp_[1]:
				rift_pos = rp
				var rift := Sprite2D.new()
				rift.texture = Art.prop_lit("rift")
				rift.scale = Vector2(0.25, 0.25)
				rift.offset = Vector2(0, -Art.prop("rift").get_size().y / 2.0 + 8.0)
				rift.position = rp
				actors.add_child(rift)
				var rl := _make_light(Color(0.55, 0.4, 0.9), 0.9, 2.2, 30.0)
				rl.position = rp + Vector2(0, -24)
				world.add_child(rl)
	# the shortcut gate
	gate_node = Sprite2D.new()
	gate_node.texture = Art.prop_lit("gate_closed")
	gate_node.scale = Vector2(0.25, 0.25)
	gate_node.offset = Vector2(0, -Art.prop("gate_closed").get_size().y / 2.0 + 8.0)
	gate_node.position = _v(L["gate"]["pos"])
	actors.add_child(gate_node)


func _make_light(col: Color, energy: float, scale: float, height: float = 20.0) -> PointLight2D:
	var l := PointLight2D.new()
	l.height = height
	l.texture = light_tex
	l.color = col
	l.energy = energy
	l.texture_scale = scale
	l.set_meta("base_e", energy)
	return l


func _embers(pos: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 1.6
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(4, -18)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.35, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = g
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	fx.add_child(p)


func _build_atmosphere() -> void:
	# rain that follows the camera
	rain = CPUParticles2D.new()
	rain.amount = 260
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(300, 10)
	rain.direction = Vector2(0.18, 1)
	rain.spread = 2.0
	rain.gravity = Vector2.ZERO
	rain.initial_velocity_min = 330.0
	rain.initial_velocity_max = 400.0
	var img := Image.create(1, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.75, 0.8, 0.95, 0.35))
	rain.texture = ImageTexture.create_from_image(img)
	rain.scale_amount_min = 0.3
	rain.scale_amount_max = 0.45
	rain.local_coords = false
	if L.get("weather", "") == "snow":
		rain.amount = 160
		rain.lifetime = 4.0
		rain.direction = Vector2(0.25, 1)
		rain.spread = 30.0
		rain.initial_velocity_min = 14.0
		rain.initial_velocity_max = 30.0
		rain.emission_rect_extents = Vector2(320, 120)
		var si := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		si.fill(Color(0.92, 0.95, 1.0, 0.8))
		rain.texture = ImageTexture.create_from_image(si)
		rain.scale_amount_min = 0.5
		rain.scale_amount_max = 1.2
		lightning_t = 99999.0
	elif L.get("ash", false):
		# Act II: falling ash and the odd ember instead of rain
		rain.amount = 140
		rain.lifetime = 3.2
		rain.direction = Vector2(0.45, 1)
		rain.spread = 25.0
		rain.initial_velocity_min = 22.0
		rain.initial_velocity_max = 48.0
		rain.emission_rect_extents = Vector2(320, 120)
		var ai := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		ai.fill(Color(0.78, 0.74, 0.72, 0.55))
		rain.texture = ImageTexture.create_from_image(ai)
		rain.scale_amount_min = 0.5
		rain.scale_amount_max = 1.0
		var rg := Gradient.new()
		rg.set_color(0, Color(1, 1, 1, 0.0))
		rg.add_point(0.15, Color(1, 1, 1, 1))
		rg.add_point(0.85, Color(1, 0.9, 0.85, 1))
		rg.set_color(1, Color(1, 0.6, 0.3, 0.0))
		rain.color_ramp = rg
		lightning_t = 99999.0
	fx.add_child(rain)
	# fireflies around the camp and the glade
	for a in areas:
		if a["id"] in ["camp", "glade", "hollow"]:
			var ff := CPUParticles2D.new()
			ff.position = a["pos"]
			ff.amount = 14
			ff.lifetime = 5.0
			ff.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			ff.emission_sphere_radius = a["r"] * 0.8
			ff.gravity = Vector2.ZERO
			ff.initial_velocity_min = 2.0
			ff.initial_velocity_max = 8.0
			ff.spread = 180.0
			var g := Gradient.new()
			g.set_color(0, Color(0.8, 1.0, 0.4, 0.0))
			g.add_point(0.5, Color(0.85, 1.0, 0.5, 0.9))
			g.set_color(1, Color(0.8, 1.0, 0.4, 0.0))
			ff.color_ramp = g
			ff.scale_amount_min = 0.4
			ff.scale_amount_max = 0.6
			fx.add_child(ff)
	# low drifting fog
	var fog := CPUParticles2D.new()
	fog.position = bounds.get_center()
	fog.amount = 40
	fog.lifetime = 14.0
	fog.texture = light_tex
	fog.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fog.emission_rect_extents = bounds.size / 2.0
	fog.gravity = Vector2.ZERO
	fog.direction = Vector2(1, 0)
	fog.spread = 20.0
	fog.initial_velocity_min = 3.0
	fog.initial_velocity_max = 8.0
	fog.scale_amount_min = 1.2
	fog.scale_amount_max = 2.2
	var fg := Gradient.new()
	fg.set_color(0, Color(0.6, 0.65, 0.75, 0.0))
	fg.add_point(0.5, Color(0.6, 0.65, 0.75, 0.09))
	fg.set_color(1, Color(0.6, 0.65, 0.75, 0.0))
	fog.color_ramp = fg
	fog.preprocess = 10.0
	world.add_child(fog)


# =====================================================================
# Main loop
# =====================================================================

func _process(delta: float) -> void:
	switch_cd -= delta
	banner_t -= delta
	_handle_global_input()
	if ui == "play":
		_update_areas()
		_update_pickups()
	if ui == "dead":
		dead_t -= delta
		if dead_t <= 0.0:
			_respawn_after_death()
	if leader != null:
		camera.global_position = leader.global_position + Vector2(0, -12)
		if trail.is_empty() or (trail.back() as Vector2).distance_to(leader.global_position) > 12.0:
			trail.append(leader.global_position)
			if trail.size() > 80:
				trail.pop_front()
	rain.global_position = camera.get_screen_center_position() + Vector2(-40, -170)
	shake_amt = move_toward(shake_amt, 0.0, 20.0 * delta)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	_update_tint(delta)
	_fade_occluders(delta)
	var tms := Time.get_ticks_msec()
	for l in flicker_lights:
		var b: float = l.get_meta("base_e")
		l.energy = b * (1.0 + sin(tms / 70.0 + l.get_instance_id()) * 0.05 + randf() * 0.04)
	if leader != null:
		if lag_hero != leader:
			lag_hero = leader
			hp_lag = float(leader.hp) / leader.max_hp
		var fr := float(leader.hp) / leader.max_hp
		hp_lag = fr if fr > hp_lag else move_toward(hp_lag, fr, delta * (0.0 if leader.hurt_t > 0.0 else 0.6))
	if ui == "play":
		for h in heroes:
			var low: bool = not h.is_dead() and float(h.hp) / h.max_hp < 0.3
			if low and not lowhp_said.get(h.hero_id, false):
				lowhp_said[h.hero_id] = true
				banter.hero_line("lowhp", h.hero_id, 0.7)
			elif float(h.hp) / h.max_hp > 0.6:
				lowhp_said[h.hero_id] = false
	if autotest:
		_autotest(delta)
	hud.queue_redraw()


func _fade_occluders(delta: float) -> void:
	var cam := camera.get_screen_center_position()
	for sp in tall_props:
		var p: Vector2 = sp.position
		if absf(p.x - cam.x) > 280.0 or absf(p.y - cam.y) > 200.0:
			continue
		var hide := false
		var half_w: float = sp.texture.get_width() * sp.scale.x * 0.5
		var height: float = sp.texture.get_height() * sp.scale.y
		for h in heroes:
			if h.is_dead() and h != leader:
				continue
			var hp: Vector2 = h.global_position
			if hp.y < p.y and hp.y > p.y - height and absf(hp.x - p.x) < half_w + 4.0:
				hide = true
				break
		if not hide:
			for e in enemies:
				if not e.is_dead() and e.global_position.distance_to(leader.global_position) < 160.0:
					var ep: Vector2 = e.global_position
					if ep.y < p.y and ep.y > p.y - height and absf(ep.x - p.x) < half_w:
						hide = true
						break
		var target := 0.3 if hide else 1.0
		sp.modulate.a = move_toward(sp.modulate.a, target, delta * 4.0)


func _update_tint(delta: float) -> void:
	var puck: Hero = hero("puck")
	lightning_t -= delta
	if lightning_t <= 0.0:
		lightning_t = randf_range(14.0, 35.0)
		flash_t = 0.35
		shake(2.0)
	flash_t -= delta
	var target := night_col
	if puck.has("haze"):
		target = Color.from_hsv(fmod(Time.get_ticks_msec() / 4000.0, 1.0), 0.45, 0.95)
	if flash_t > 0.0:
		var k := 1.0 if (flash_t > 0.25 or (flash_t > 0.08 and flash_t < 0.15)) else 0.0
		tint.color = target.lerp(Color(0.85, 0.9, 1.0), k * 0.8)
	else:
		tint.color = tint.color.lerp(target, 4.0 * delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		using_mouse = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		using_mouse = false
	if event is InputEventKey and event.is_pressed() and event.physical_keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if ui in ["title", "pause", "options", "controls", "credits"] and not autotest:
		_menu_input(event)
		return
	if ui == "talk":
		banter.talk_input(event)
		return
	if ui == "inventory" and not autotest:
		inv.handle(event)
	if ui == "shop" and not autotest:
		camp.handle(event)
		return
	if ui == "level" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = hud.get_local_mouse_position()
		if not feat_offer.is_empty():
			for k in feat_offer.size():
				if _feat_card(k).has_point(m):
					choose_feat(k)
		elif Art.ui("lvl_panel") != null:
			var rr := _lvl_rects()
			var lm: Dictionary = Art.ui_info("shrine_panel")
			for i in 4:
				if _sub(rr["right"], lm["rows"][i]).has_point(m):
					shrine_i = i
					_shrine_do(i)
			for pf in Art.ui_info("lvl_panel")["plus"]:
				if _sub(rr["left"], pf).has_point(m):
					try_level_up(leader)
		elif Rect2(480.0 / 2.0 - 70.0, 146.0, 140.0, 14.0).has_point(m):
			try_level_up(leader)
		get_viewport().set_input_as_handled()
	if ui == "level" and feat_offer.is_empty() and event is InputEventKey and event.pressed and not event.is_echo():
		match event.physical_keycode:
			KEY_UP, KEY_W:
				shrine_i = (shrine_i + 3) % 4
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				shrine_i = (shrine_i + 1) % 4
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				_shrine_do(shrine_i)
				get_viewport().set_input_as_handled()
				return
	var pressed: bool = (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if ui == "select" and pressed and (event is InputEventKey and event.physical_keycode == KEY_ESCAPE or event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B):
		set_ui("title")
		get_viewport().set_input_as_handled()
		return
	elif ui == "select" and pressed:
		var key: int = event.physical_keycode if event is InputEventKey else -1
		if key in [KEY_A, KEY_LEFT]:
			select_i = (select_i + 3) % 4
		elif key in [KEY_D, KEY_RIGHT]:
			select_i = (select_i + 1) % 4
		elif key in [KEY_1, KEY_2, KEY_3, KEY_4]:
			select_i = key - KEY_1
		elif event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			select_i = (select_i + (1 if event.button_index == JOY_BUTTON_DPAD_RIGHT else 3)) % 4
		elif key in [KEY_ENTER, KEY_SPACE, KEY_F] or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A) or event is InputEventMouseButton:
			if event is InputEventMouseButton:
				var mx: float = hud.get_local_mouse_position().x
				select_i = clamp(int((mx - 20.0) / 110.0), 0, 3)
			set_leader(heroes[select_i])
			menu_back = "pause"
			set_ui("play")
			banter.talk("intro")
			show_banner("THE HOLLOWMARCH OUTSKIRTS", "Act I  -  you are %s" % leader.display_name, Color(0.85, 0.8, 0.7))
		get_viewport().set_input_as_handled()


func _handle_global_input() -> void:
	if autotest or ui == "title" or Engine.get_process_frames() == menu_frame:
		return
	if ui == "play" and Input.is_action_just_pressed("pause"):
		set_ui("pause")
		return
	if ui == "level":
		if not feat_offer.is_empty():
			# a feat must be chosen before leaving the shrine
			for k in 3:
				if Input.is_action_just_pressed("ability_%d" % (k + 1)):
					choose_feat(k)
			return
		if Input.is_action_just_pressed("ability_1") or Input.is_action_just_pressed("dash") or (Input.is_action_just_pressed("attack") and not using_mouse):
			try_level_up(leader)
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("level_menu"):
			set_ui("play")
		return
	if ui == "inventory":
		if Input.is_action_just_pressed("inventory") or Input.is_action_just_pressed("pause"):
			set_ui("play")
		return
	if ui != "play":
		return
	if Input.is_action_just_pressed("interact"):
		interact()
	if Input.is_action_just_pressed("inventory"):
		set_ui("inventory")
	if Input.is_action_just_pressed("level_menu") and leader.global_position.distance_to(shrine_pos) < 50.0:
		set_ui("level")


func _cycle_hero() -> void:
	var i := heroes.find(leader)
	for k in range(1, 5):
		var h: Hero = heroes[(i + k) % 4]
		if not h.is_dead():
			try_switch(h)
			return


func try_switch(h: Hero) -> void:
	if h == leader or h.is_dead() or switch_cd > 0.0:
		return
	switch_cd = 1.5
	set_leader(h)


func set_leader(h: Hero) -> void:
	if leader != null:
		leader.controlled = false
	leader = h
	h.controlled = not autotest


func show_banner(text: String, sub: String = "", col: Color = Color(0.9, 0.85, 0.7), t: float = 3.0) -> void:
	banner = text
	banner_sub = sub
	banner_col = col
	banner_t = t


# =====================================================================
# Areas, encounters, seals, gate
# =====================================================================

func area_at(p: Vector2) -> Dictionary:
	for a in areas:
		if p.distance_to(a["pos"]) < a["r"]:
			return a
	return {}


func _update_areas() -> void:
	if active_area == "":
		for a in areas:
			# sealed arenas close once you're well inside; open areas wake as you come near
			var reach: float = a["r"] * (0.72 if a["seal"] else 1.0) + (0.0 if a["seal"] else 30.0)
			if area_state[a["id"]] == "idle" and not a["encounter"].is_empty() and leader.global_position.distance_to(a["pos"]) < reach:
				_start_encounter(a)
				break
	else:
		var list: Array = area_enemies[active_area]
		if list.all(func(e): return e.is_dead()):
			_clear_encounter(active_area)
			return
		if not combat_music and list.any(func(e): return not e.is_dead() and e.aware):
			combat_music = true
			Sfx.music("combat", 1.0)
			banter.party_line("encounter", 0.6)
		# walking away from an open fight: the survivors go back to their posts
		var aa: Dictionary = areas.filter(func(x): return x["id"] == active_area)[0]
		if not aa["seal"] and leader.global_position.distance_to(aa["pos"]) > aa["r"] + 190.0:
			_on_log("You leave %s behind. Its dead stay dead; the rest wait." % aa["name"])
			for e in list:
				if not e.is_dead():
					e.aware = false
					e.target = null
			active_area = ""
			area_state[aa["id"]] = "idle"
			Sfx.music("explore", 3.0)


func _start_encounter(a: Dictionary) -> void:
	active_area = a["id"]
	var bi := _bossinfo(a)
	var boss_fresh: bool = a["boss"] and not bosses_dead.has(a["id"])
	if boss_fresh:
		Sfx.music(bi.get("music", "boss"), 0.8)
		Sfx.play("roar", null, -1.0, 0.0)
		banter.talk(bi["intro"])
	elif a["seal"]:
		Sfx.music("combat", 1.0)
		banter.party_line("encounter", 0.6)
	combat_music = boss_fresh or a["seal"]
	if autotest:
		print("  start %s at t=%.1f" % [a["id"], test_t])
	area_state[a["id"]] = "active"
	var from_dir: Vector2 = (leader.global_position - a["pos"]).normalized()
	var list: Array = area_enemies.get(a["id"], []).filter(func(e): return is_instance_valid(e) and not e.is_dead())
	var kinds: Array = a["encounter"]
	if list.is_empty():
		for i in kinds.size():
			var e := Enemy.new()
			e.main = self
			e.setup(kinds[i])
			if a["seal"]:
				var ang := from_dir.angle() + PI + (i - kinds.size() / 2.0) * 0.45
				e.position = a["pos"] + Vector2.from_angle(ang) * a["r"] * (0.5 if not kinds[i] in Enemy.BOSSES else 0.3)
				e.aware = true
			else:
				# scattered around the area, minding their own business until they see you
				for tries in 12:
					var p: Vector2 = a["pos"] + Vector2.from_angle(randf() * TAU) * a["r"] * randf_range(0.15, 0.8)
					e.position = p
					if p.distance_to(leader.global_position) > 120.0 and is_walkable(p, 8.0):
						break
				e.aware = false
			e.home = a["pos"]
			e.post = e.position
			e.leash = a["r"] + 150.0
			actors.add_child(e)
			enemies.append(e)
			list.append(e)
	area_enemies[a["id"]] = list
	if autotest:
		print("    spawned %d in %s (%d walkable)" % [list.size(), a["id"], list.filter(func(e): return is_walkable(e.global_position, 4.0)).size()])
	# seal the exits with thorns
	for s in L["seals"].get(a["id"], []):
		var node := Sprite2D.new()
		node.texture = Art.prop_lit("thorns")
		node.offset = Vector2(0, -48)
		node.position = _v(s["pos"])
		node.scale = Vector2(0.4, 0.4)
		actors.add_child(node)
		seal_blockers.append({"pos": _v(s["pos"]), "r": float(s["r"]), "node": node})
	# the party gathers inside (like a fog gate)
	for h in (heroes if a["seal"] else []):
		if not h.is_dead() and h.global_position.distance_to(a["pos"]) > a["r"] - 20.0:
			h.position = a["pos"] + (leader.global_position - a["pos"]).normalized() * (a["r"] - 40.0) + Vector2(randf_range(-12, 12), randf_range(-12, 12))
	if a["boss"]:
		show_banner(bi["title"], bi["sub"], Color(0.85, 0.2, 0.12), 3.5)
	elif a["seal"]:
		show_banner(a["name"].to_upper(), "The way closes behind you", Color(0.85, 0.8, 0.7), 2.5)
	else:
		show_banner(a["name"].to_upper(), "", Color(0.85, 0.8, 0.7), 2.0)
	_on_log("%s: %s" % [a["name"], ", ".join(kinds.map(func(k): return k.split("@")[0].replace("_", " ")))])


func _clear_encounter(id: String) -> void:
	Sfx.music("explore", 3.0)
	var ca: Dictionary = areas.filter(func(x): return x["id"] == id)[0]
	if ca["boss"]:
		if ca["final"] and Run.act >= Run.LAST_ACT:
			ending = true
		banter.talk(_bossinfo(ca)["dead"])
	else:
		var br: Hero = hero("brokk")
		if not br.is_dead() and randf() < 0.3 and kills_by.get("brokk", 0) > 0:
			var mine: int = kills_by.get("brokk", 0)
			var his: int = kills_by.get("average", 0)
			banter.quip(br, ("That's %d for me, %d for the barbarian. Keep up, lad." % [mine, his]) if mine >= his else ("%d for me. %d for him. ...He's cheating somehow." % [mine, his]))
		else:
			banter.party_line("clear", 0.7)
	if autotest:
		print("  cleared %s at t=%.1f" % [id, test_t])
	area_state[id] = "cleared"
	active_area = ""
	areas_ever_cleared[id] = true
	for h in heroes:
		if h != leader:
			while h.level < min(1 + areas_ever_cleared.size(), leader.level):
				h.level_up()
	for s in seal_blockers:
		s["node"].queue_free()
	seal_blockers.clear()
	var a: Dictionary = areas.filter(func(x): return x["id"] == id)[0]
	var drops := 3 if a["boss"] else 1 + int(randf() < 0.5)
	for i in drops:
		drop_loot(a["pos"] + Vector2(randf_range(-20, 20), randf_range(-10, 14)), 0.15 if a["boss"] else 0.0)
	if a["boss"]:
		bosses_dead[id] = true
		if a["final"]:
			boss_dead = true
		show_banner("VICTORY ACHIEVED", _bossinfo(a)["victory"], Color(0.95, 0.8, 0.4), 6.0)
		save_now()
	else:
		show_banner("AREA CLEARED", a["name"], Color(0.8, 0.85, 0.7), 2.5)


func _reset_area(id: String) -> void:
	for e in area_enemies.get(id, []):
		enemies.erase(e)
		e.queue_free()
	area_enemies[id] = []
	var a: Dictionary = areas.filter(func(x): return x["id"] == id)[0]
	if a["encounter"].is_empty() or (a["boss"] and bosses_dead.has(id)):
		area_state[id] = "cleared"
	else:
		area_state[id] = "idle"
	if id == active_area:
		active_area = ""
		for s in seal_blockers:
			s["node"].queue_free()
		seal_blockers.clear()


func interact() -> void:
	var p := leader.global_position
	if active_area == "" and camp.try_interact(p):
		return
	if p.distance_to(shrine_pos) < 50.0:
		try_rest()
		return
	if Run.act < Run.LAST_ACT and boss_dead and p.distance_to(rift_pos) < 46.0 and active_area == "":
		enter_rift()
		return
	var g := _v(L["gate"]["pos"])
	if not gate_open and p.distance_to(g) < 50.0:
		if (p - g).dot(_v(L["gate"].get("open_from", [1, 0]))) > 0.0:
			open_gate()
		else:
			float_text(g + Vector2(0, -50), "Locked from the other side.", Color(0.8, 0.75, 0.65), 1.5)
		return
	for b in loot_bags:
		if p.distance_to(b["pos"]) < 24.0:
			pickup(b)
			return


## Act defaults: Act I's level data predates boss info, so the Iron Brother's lives here.
func _bossinfo(a: Dictionary) -> Dictionary:
	var d := {"title": "THE IRON BROTHER", "sub": "Average's father never beat him", "intro": "boss_intro", "dead": "boss_dead",
		"victory": "The Iron Brother is dead. Average will not shut up about it.", "music": "boss"}
	d.merge(a.get("bossinfo", {}), true)
	return d


func enter_rift() -> void:
	rift_pending = true
	Sfx.play("shrine", rift_pos, 0.0, 0.0)
	ring(rift_pos, 60.0, Color(0.7, 0.5, 1.0))
	if autotest:
		Run.goto_act(Run.act + 1, self)
		return
	banter.talk("rift_enter" if Run.act == 1 else "rift_enter_%d" % Run.act, false)


func open_gate() -> void:
	Sfx.play("gate", gate_node.global_position if gate_node else null)
	gate_open = true
	gate_node.texture = Art.prop_lit("gate_open")
	show_banner("SHORTCUT OPENED", "The iron gate grinds open", Color(0.8, 0.85, 0.9), 2.5)
	shake(3.0)


func try_rest() -> void:
	if active_area != "":
		float_text(shrine_pos + Vector2(0, -40), "You cannot rest with enemies near", Color(0.8, 0.3, 0.3), 1.5)
		return
	for h in heroes:
		h.rest()
	Sfx.play("shrine", null, -2.0, 0.0)
	draughts = draught_max
	ring(shrine_pos, 70.0, Color(0.9, 0.9, 1.0))
	# resting brings the dead back (except the Iron Brother)
	for a in areas:
		if not a["boss"] or not bosses_dead.has(a["id"]):
			_reset_area(a["id"])
	_on_log("The party rests at the Moth Shrine. Enemies return.")
	save_now()
	if not banter.seen.has("shrine_first") and not autotest:
		banter.talk("shrine_first")
		return
	set_ui("level")
	if randf() < 0.5:
		banter.say("rest")


## Companions train alongside you: they never fall behind your level.
func party_catch_up() -> void:
	for o in heroes:
		if o == leader:
			continue
		var before: int = o.level
		while o.level < leader.level:
			o.level_up()
		if o.level > before:
			float_text(o.global_position + Vector2(0, -o.sprite_h - 6), "%s: level %d" % [o.display_name, o.level], Color(1.0, 0.9, 0.55), 1.6)
			_on_log("%s reaches level %d" % [o.display_name, o.level])


func choose_feat(i: int) -> void:
	if i < 0 or i >= feat_offer.size():
		return
	var id: String = feat_offer[i]
	leader.add_feat(id)
	feat_offer = []
	Sfx.play("ui_confirm", null, -2.0, 0.0)
	float_text(leader.global_position + Vector2(0, -leader.sprite_h - 14), Feats.info(id)["name"], Color(1.0, 0.9, 0.55), 1.8)
	_on_log("%s learns %s: %s" % [leader.display_name, Feats.info(id)["name"], Feats.info(id)["desc"]])
	save_now()


func _feat_card(i: int) -> Rect2:
	return Rect2(480.0 / 2.0 - 138.0 + i * 92.0, 100.0, 88.0, 122.0)


func try_level_up(h: Hero) -> void:
	if not feat_offer.is_empty():
		return
	var cost := Hero.level_cost(h.level)
	if starlight < cost:
		float_text(h.global_position + Vector2(0, -40), "Need %d Starlight" % cost, Color(0.8, 0.5, 0.5), 1.2)
		return
	starlight -= cost
	h.level_up()
	feat_offer = Feats.offer(h.hero_id, h.feats)
	if autotest and not feat_offer.is_empty():
		choose_feat(0)
	Sfx.play("levelup", null, -2.0, 0.0)
	_on_log("%s reaches level %d" % [h.display_name, h.level])
	party_catch_up()
	save_now()
	if randf() < 0.5:
		banter.say("levelup")


# =====================================================================
# Death, Starlight moth, loot
# =====================================================================

func on_death(c: Combatant) -> void:
	if c is Enemy:
		kills += 1
		if c.last_attacker is Hero:
			c.last_attacker.since_kill = 0.0
			kills_by[c.last_attacker.hero_id] = int(kills_by.get(c.last_attacker.hero_id, 0)) + 1
			var av: Hero = hero("average")
			if c.last_attacker != av and c.damaged_by.has(av) and not av.is_dead() and randf() < 0.3:
				banter.hero_line("kill_steal", "average")
		var mult := 1.0 + (0.15 if leader.prop("fortune") else 0.0) + (0.25 if leader.prop("starlit") else 0.0)
		starlight += int(c.xp * mult)
		# bosses leave their own named piece
		for uid in Items.UNIQUES:
			if Items.UNIQUES[uid].get("boss", "") == c.kind:
				_place_loot(c.global_position + Vector2(0, 10), Items.make_unique(uid))
		Sfx.play("starlight", c.global_position, -12.0)
		var avg: Hero = hero("average")
		if not avg.is_dead() and watched(avg) and c.last_attacker == avg:
			avg.glory = min(100.0, avg.glory + (30.0 if avg.has_feat("glory_hound") else 15.0))
		if focus_target == c:
			focus_target = null
		if c.summoner == null and randf() < (0.12 if c.kind == "ghoul" else 0.3):
			drop_loot(c.global_position, 0.0)
	elif c is Hero:
		if c == leader:
			_party_wipe(c.global_position)


func _party_wipe(pos: Vector2) -> void:
	Sfx.play("you_died", null, 0.0, 0.0)
	Sfx.music("", 0.5)
	deaths += 1
	ui = "dead"
	dead_t = 4.0 if not autotest else 1.0
	if not moth_drop.is_empty():
		moth_drop["node"].queue_free()
		_on_log("The old Starlight moth fades away.")
	moth_drop = {}
	if starlight > 0:
		_spawn_moth(pos, starlight)
		starlight = 0
	_on_log("YOU DIED. Your Starlight waits where you fell.")


func _spawn_moth(pos: Vector2, amount: int) -> void:
	if true:
		var n := AnimatedSprite2D.new()
		var sf := SpriteFrames.new()
		sf.set_animation_speed("default", 6.0)
		sf.add_frame("default", Art.prop("moth_0"))
		sf.add_frame("default", Art.prop("moth_1"))
		n.sprite_frames = sf
		n.play("default")
		n.scale = Vector2(0.25, 0.25)
		n.position = pos + Vector2(0, -10)
		fx.add_child(n)
		moth_drop = {"pos": pos, "amount": amount, "node": n}


func _respawn_after_death() -> void:
	ui = "play"
	if active_area != "":
		_reset_area(active_area)
	for i in heroes.size():
		var h: Hero = heroes[i]
		h.rest()
		h.position = shrine_pos + Vector2(-24 + i * 16, 50)
		h.velocity = Vector2.ZERO
	draughts = draught_max
	trail.clear()
	route_i = 0
	show_banner("THE MOTH SHRINE", "You wake by the fire", Color(0.75, 0.8, 1.0), 2.5)


func drop_loot(pos: Vector2, luck: float) -> void:
	# now and then a sigil stone instead of gear (bosses: always one extra)
	if randf() < 0.18 + luck:
		_place_loot(pos + Vector2(randf_range(-8, 8), 6), Items.make_sigil())
		if randf() < 0.6:
			return
	var slot: String = ["weapon", "armor", "trinket"].pick_random()
	_place_loot(pos, Items.make(slot, luck))


func _place_loot(pos: Vector2, it: Dictionary) -> void:
	var sp := Sprite2D.new()
	var sig: bool = it["slot"] == "sigil" and Art.tex("sigil_" + str(it["sigil"])) != null
	sp.texture = Art.tex("sigil_" + str(it["sigil"])) if sig else Art.prop("loot")
	sp.scale = Vector2(0.13, 0.13) if sig else Vector2(0.25, 0.25)
	sp.offset = Vector2(0, -48) if sig else Vector2(0, -20)
	sp.position = pos
	actors.add_child(sp)
	var glow := _make_light(Items.SIGILS[it["sigil"]]["col"] if it["slot"] == "sigil" else Items.RARITY[it["rarity"]], 0.8, 0.5)
	glow.position = Vector2(0, -4)
	sp.add_child(glow)
	loot_bags.append({"pos": pos, "item": it, "node": sp})


func pickup(bag: Dictionary) -> void:
	Sfx.play("loot", null, -3.0)
	loot_bags.erase(bag)
	bag["node"].queue_free()
	var it: Dictionary = bag["item"]
	var col: Color = Items.RARITY[it["rarity"]]
	if it["slot"] == "sigil":
		if self.bag.size() >= BAG_SIZE:
			starlight += inv.value(it)
			float_text(bag["pos"] + Vector2(0, -16), "Bag full: sigil salvaged", col, 2.0)
			return
		self.bag.append(it)
		float_text(bag["pos"] + Vector2(0, -16), "%s  (socket it: I, then R)" % Items.describe(it, leader.hero_id), Items.SIGILS[it["sigil"]]["col"], 2.6)
		_on_log("Into the bag: %s" % Items.describe(it, leader.hero_id))
		# the others find sigils of their own now and then
		for h in heroes:
			if h != leader and randf() < 0.35:
				for slot in ["weapon", "armor", "trinket"].duplicate().map(func(x): return x):
					if not h.gear[slot].is_empty() and Items.socket(h.gear[slot], Items.SIGILS.keys().pick_random()):
						h.recalc()
						_on_log("%s sockets a sigil into their %s" % [h.display_name, slot])
						break
		if autotest:
			_auto_socket(leader)
		return
	companion_finds(it)
	# an empty slot is filled straight away; everything else waits in the bag for you to choose
	if leader.gear[it["slot"]].is_empty():
		leader.equip(it)
		float_text(bag["pos"] + Vector2(0, -16), "%s: %s" % [leader.display_name, Items.describe(it, leader.hero_id)], col, 2.4)
		_on_log("%s equips %s (%s)" % [leader.display_name, Items.describe(it, leader.hero_id), Items.details(it)])
		return
	if self.bag.size() >= BAG_SIZE:
		var v: int = inv.value(it)
		starlight += v
		float_text(bag["pos"] + Vector2(0, -16), "Bag full: %s salvaged (+%d)" % [Items.describe(it, leader.hero_id), v], col, 2.0)
		return
	self.bag.append(it)
	var up := Items.score(it) > Items.score(leader.gear[it["slot"]])
	float_text(bag["pos"] + Vector2(0, -16), "%s%s" % [Items.describe(it, leader.hero_id), "  (upgrade! press I)" if up else ""], col, 2.4)
	_on_log("Into the bag: %s" % Items.describe(it, leader.hero_id))
	if autotest:
		_auto_equip(leader)


## Companions keep pace: whenever you find something, each of them turns up something
## of the same quality for themselves and wears it if it beats what they have.
func companion_finds(found: Dictionary) -> void:
	var luck: float = {"normal": 0.0, "magic": 0.1, "rare": 0.2, "unique": 0.3}[found["rarity"]]
	for h in heroes:
		if h == leader or randf() > 0.85:
			continue
		var it := Items.make(["weapon", "armor", "trinket"].pick_random(), luck)
		if Items.score(it) > Items.score(h.gear[it["slot"]]):
			h.equip(it)
			float_text(h.global_position + Vector2(0, -h.sprite_h - 10), "%s: %s" % [h.display_name, Items.describe(it, h.hero_id)], Items.RARITY[it["rarity"]], 2.2)
			_on_log("%s finds and equips %s" % [h.display_name, Items.describe(it, h.hero_id)])


## Socket every sigil in the bag into the first free socket of h's gear (autotest).
func _auto_socket(h: Hero) -> void:
	for it in self.bag.duplicate():
		if it["slot"] != "sigil":
			continue
		for slot in ["weapon", "armor", "trinket"]:
			if not h.gear[slot].is_empty() and Items.socket(h.gear[slot], it["sigil"]):
				self.bag.erase(it)
				h.recalc()
				_on_log("%s sockets a %s" % [h.display_name, Items.describe(it, h.hero_id)])
				break


## Wear the best things in the bag (used by the autotest leader).
func _auto_equip(h: Hero) -> void:
	for it in self.bag.duplicate():
		if it["slot"] == "sigil":
			continue
		if Items.score(it) > Items.score(h.gear[it["slot"]]):
			self.bag.erase(it)
			var old: Dictionary = h.equip(it)
			if not old.is_empty():
				self.bag.append(old)


func _update_pickups() -> void:
	for b in loot_bags.duplicate():
		if leader.global_position.distance_to(b["pos"]) < 14.0:
			pickup(b)
	if not moth_drop.is_empty():
		var n: Node2D = moth_drop["node"]
		n.position = moth_drop["pos"] + Vector2(0, -12 + sin(Time.get_ticks_msec() / 300.0) * 3.0)
		for h in heroes:
			if not h.is_dead() and h.global_position.distance_to(moth_drop["pos"]) < 16.0:
				starlight += int(moth_drop["amount"])
				float_text(moth_drop["pos"] + Vector2(0, -20), "Starlight reclaimed (+%d)" % moth_drop["amount"], Color(0.85, 0.9, 1.0), 2.0)
				n.queue_free()
				moth_drop = {}
				break


# =====================================================================
# Walkability
# =====================================================================

var walk_img: Image = null
var walk_scale := 1.0


## Hand-drawn layouts carry a walk mask (white = walkable) instead of circles and roads.
func _mask_ok(p: Vector2) -> bool:
	var x := int(p.x * walk_scale)
	var y := int(p.y * walk_scale)
	if x < 0 or y < 0 or x >= walk_img.get_width() or y >= walk_img.get_height():
		return false
	return walk_img.get_pixel(x, y).r > 0.5


func is_walkable(p: Vector2, r: float = 0.0) -> bool:
	if walk_img != null:
		var h := r * 0.5
		if not (_mask_ok(p) and _mask_ok(p + Vector2(h, 0)) and _mask_ok(p - Vector2(h, 0)) and _mask_ok(p + Vector2(0, h)) and _mask_ok(p - Vector2(0, h))):
			return false
		for s in solids:
			if p.distance_to(s["pos"]) < s["r"] + r * 0.5:
				return false
		for s in seal_blockers:
			if p.distance_to(s["pos"]) < s["r"] * 0.6 + r:
				return false
		if not gate_open and p.distance_to(_v(L["gate"]["pos"])) < float(L["gate"]["r"]) + r * 0.5:
			return false
		return true
	var ok := false
	for a in areas:
		if p.distance_to(a["pos"]) <= a["r"] - r * 0.5:
			ok = true
			break
	if not ok:
		for pa in paths:
			if _seg_dist(p, pa["a"], pa["b"]) <= pa["hw"] - r * 0.5:
				ok = true
				break
	if not ok:
		return false
	for s in solids:
		if p.distance_to(s["pos"]) < s["r"] + r * 0.5:
			return false
	for s in seal_blockers:
		if p.distance_to(s["pos"]) < s["r"] * 0.6 + r:
			return false
	if not gate_open and p.distance_to(_v(L["gate"]["pos"])) < float(L["gate"]["r"]) + r * 0.5:
		return false
	return true


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func keep_walkable(before: Vector2, after: Vector2, r: float) -> Vector2:
	if is_walkable(after, r):
		return after
	var sx := Vector2(after.x, before.y)
	if is_walkable(sx, r):
		return sx
	var sy := Vector2(before.x, after.y)
	if is_walkable(sy, r):
		return sy
	if is_walkable(before, r):
		return before
	# already wedged into an edge: let them move anywhere that is still ground, so they can get out
	if is_walkable(after, 0.0) and is_walkable(after, r * 0.5):
		return after
	# stuck somewhere invalid (e.g. a seal closed on us): nudge toward the nearest area
	var best: Dictionary = areas[0]
	for a in areas:
		if before.distance_to(a["pos"]) < before.distance_to(best["pos"]):
			best = a
	return before.move_toward(best["pos"], 2.0)


func clamp_to_arena(p: Vector2) -> Vector2:
	return p


func blocked(pos: Vector2) -> bool:
	return not is_walkable(pos)


func segment_walkable(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 10.0) + 1
	for i in n + 1:
		if not is_walkable(a.lerp(b, float(i) / n), 6.0):
			return false
	return true


## Where a companion should head for a goal: straight there if clear, else along the leader's trail.
func follow_point(c: Combatant, goal: Vector2) -> Vector2:
	if segment_walkable(c.global_position, goal) or trail.is_empty():
		return goal
	var best := 0
	var bd := INF
	for i in trail.size():
		var d := c.global_position.distance_to(trail[i])
		if d < bd:
			bd = d
			best = i
	return trail[min(best + 2, trail.size() - 1)]


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, JOY_AXIS_LEFT_X, -1.0],
		"move_right": [KEY_D, JOY_AXIS_LEFT_X, 1.0],
		"move_up": [KEY_W, JOY_AXIS_LEFT_Y, -1.0],
		"move_down": [KEY_S, JOY_AXIS_LEFT_Y, 1.0],
	}
	for action_name in map:
		_add_action(action_name)
		_key(action_name, map[action_name][0])
		var jm := InputEventJoypadMotion.new()
		jm.axis = map[action_name][1]
		jm.axis_value = map[action_name][2]
		InputMap.action_add_event(action_name, jm)
	_bind("attack", [KEY_J], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X])
	_bind("special", [KEY_K], [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_Y])
	_bind("cast", [KEY_Q], [], [], JOY_AXIS_TRIGGER_RIGHT)
	_bind("dash", [KEY_SPACE], [], [JOY_BUTTON_A])
	_bind("parry", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("ability_1", [KEY_1], [], [])
	_bind("ability_2", [KEY_2], [], [])
	_bind("ability_3", [KEY_3], [], [])
	_bind("drink", [KEY_E], [], [JOY_BUTTON_B])
	_bind("interact", [KEY_F], [], [JOY_BUTTON_BACK])
	_bind("next_hero", [KEY_TAB], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("hero_1", [KEY_F1], [], [JOY_BUTTON_DPAD_UP])
	_bind("hero_2", [KEY_F2], [], [JOY_BUTTON_DPAD_RIGHT])
	_bind("hero_3", [KEY_F3], [], [JOY_BUTTON_DPAD_DOWN])
	_bind("hero_4", [KEY_F4], [], [JOY_BUTTON_DPAD_LEFT])
	_bind("command", [KEY_C], [], [JOY_BUTTON_RIGHT_STICK])
	_bind("inventory", [KEY_I], [], [])
	_bind("pause", [KEY_ESCAPE], [], [JOY_BUTTON_START])
	_bind("level_menu", [KEY_L], [], [])


func _add_action(n: String) -> void:
	if not InputMap.has_action(n):
		InputMap.add_action(n, 0.3)


func _key(n: String, k: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	InputMap.action_add_event(n, e)


func _bind(n: String, keys: Array, mouse: Array, pads: Array, trigger_axis: int = -1) -> void:
	_add_action(n)
	for k in keys:
		_key(n, k)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(n, e)
	for b in pads:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(n, e)
	if trigger_axis >= 0:
		var t := InputEventJoypadMotion.new()
		t.axis = trigger_axis
		t.axis_value = 1.0
		InputMap.action_add_event(n, t)


# =====================================================================
# Main loop
# =====================================================================



func all_combatants() -> Array:
	return heroes + enemies


func hero(id: String) -> Hero:
	return heroes[HERO_IDS.find(id)]


func in_area(attacker: Combatant, a: Dictionary, t: Combatant) -> bool:
	match a.get("shape", "arc"):
		"arc":
			var to := t.global_position - attacker.global_position
			var d := to.length()
			if d > a.get("reach", 20.0) + t.radius:
				return false
			if d < t.radius + 2.0:
				return true
			return absf(attacker.facing.angle_to(to)) <= deg_to_rad(a.get("arc", 90.0)) / 2.0 + 0.15
		"circle":
			var c: Vector2 = a.get("_point", attacker.global_position)
			return t.global_position.distance_to(c) <= a.get("radius", 30.0) + t.radius
		"line":
			var rel := t.global_position - attacker.global_position
			var along := rel.dot(attacker.facing)
			var across := absf(rel.dot(attacker.facing.orthogonal()))
			return along > 0.0 and along < a.get("reach", 100.0) and across < a.get("width", 6.0) + t.radius
	return false


func targets_in_area(attacker: Combatant, a: Dictionary) -> Array:
	var out := []
	for t in all_combatants():
		if t == attacker or t.is_dead():
			continue
		if t.team == attacker.team and not a.get("any_team", false):
			continue
		if in_area(attacker, a, t):
			out.append(t)
	return out


func is_flanked(t: Combatant, attacker: Combatant) -> bool:
	var to_att := (attacker.global_position - t.global_position).normalized()
	var allies: Array = heroes if attacker.team == "hero" else enemies
	for ally in allies:
		if ally == attacker or ally.is_dead():
			continue
		var to_ally: Vector2 = ally.global_position - t.global_position
		if to_ally.length() < t.radius + 22.0 and to_att.dot(to_ally.normalized()) < -0.4:
			return true
	return false


func watched(h: Hero) -> bool:
	for o in heroes:
		if o != h and not o.is_dead() and o.global_position.distance_to(h.global_position) < 120.0:
			return true
	return false


func taunter() -> Combatant:
	var avg: Hero = hero("average")
	return avg if avg.has("taunting") and not avg.is_dead() else null


func nearest_hero(pos: Vector2) -> Combatant:
	var best: Combatant = null
	var bd := INF
	for h in heroes:
		if h.is_dead():
			continue
		var d := pos.distance_to(h.global_position)
		if d < bd:
			bd = d
			best = h
	return best


func nearest_any(c: Combatant) -> Combatant:
	var best: Combatant = null
	var bd := INF
	for o in all_combatants():
		if o == c or o.is_dead():
			continue
		var d := c.global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = o
	return best


func nearest_enemy_to(pos: Vector2) -> Combatant:
	var best: Combatant = null
	var bd := INF
	for e in enemies:
		if e.is_dead():
			continue
		var d := pos.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func nearest_enemy_dist(pos: Vector2) -> float:
	var e := nearest_enemy_to(pos)
	return INF if e == null else pos.distance_to(e.global_position)


func nearest_enemy_except(pos: Vector2, except: Combatant, max_d: float) -> Combatant:
	var best: Combatant = null
	var bd := max_d
	for e in enemies:
		if e == except or e.is_dead():
			continue
		var d := pos.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func enemies_within(pos: Vector2, r: float) -> int:
	var n := 0
	for e in enemies:
		if not e.is_dead() and e.global_position.distance_to(pos) <= r:
			n += 1
	return n


func nearest_fallen(pos: Vector2, r: float) -> Hero:
	var best: Hero = null
	var bd := r
	for h in heroes:
		if h.is_dead() and h.global_position.distance_to(pos) < bd:
			bd = h.global_position.distance_to(pos)
			best = h
	return best


func casting_enemy(pos: Vector2, r: float) -> Combatant:
	for e in enemies:
		if not e.is_dead() and e.state == Combatant.State.WINDUP and e.action.get("is_spell", false) and e.global_position.distance_to(pos) < r:
			return e
	return null


## Returns the source position of a telegraphed attack about to hit c, or null.
func danger_at(c: Combatant) -> Variant:
	for em in embers.duplicate():
		if not is_instance_valid(em):
			embers.erase(em)
			continue
		if not em.landed and em.fuse - em.age < 0.6 and c.global_position.distance_to(em.global_position) < em.radius + c.radius + 4.0:
			return em.global_position
	for e in enemies:
		if e.is_dead() or e.state != Combatant.State.WINDUP or e.action_timer > 0.35:
			continue
		if e.action.get("custom") != null and e.action.get("shape") == "line" and not e.action.get("dodge_line", false):
			continue
		if in_area(e, e.action, c):
			return e.action.get("_point", e.global_position)
	return null


## Seconds until the soonest telegraphed blow that would hit c lands (INF if none).
func danger_timer(c: Combatant) -> float:
	var best := INF
	for e in enemies:
		if e.is_dead() or e.state != Combatant.State.WINDUP or (e.action.get("shape") == "line" and not e.action.get("dodge_line", false)):
			continue
		if in_area(e, e.action, c):
			best = min(best, e.action_timer)
	return best


func flee_vector(c: Combatant) -> Vector2:
	var v := Vector2.ZERO
	for e in enemies:
		if e.is_dead():
			continue
		var to: Vector2 = c.global_position - e.global_position
		if to.length() < 80.0:
			v += to.normalized() * (80.0 - to.length()) / 80.0
	v += -c.global_position.normalized() * 0.15  # stay away from walls
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


func separation(c: Combatant) -> Vector2:
	var v := Vector2.ZERO
	for o in all_combatants():
		if o == c or o.is_dead():
			continue
		var to: Vector2 = c.global_position - o.global_position
		var min_d: float = c.radius + o.radius + 4.0
		if to.length() < min_d and to.length() > 0.01:
			v += to.normalized() * (min_d - to.length()) / min_d
	for p in solids:
		var to2: Vector2 = c.global_position - p["pos"]
		var md: float = p["r"] + c.radius + 8.0
		if to2.length() < md:
			v += to2.normalized().orthogonal() * 0.8 + to2.normalized() * 0.5
	return v


## Bends a desired move direction around the standing stones.
func steer(c: Combatant, desired: Vector2) -> Vector2:
	if desired.length() < 0.05:
		return desired
	var dir := desired.normalized()
	for p in solids:
		var to: Vector2 = p["pos"] - c.global_position
		var ahead := to.dot(dir)
		if ahead <= 0.0 or ahead > 40.0:
			continue
		var lateral := to - dir * ahead
		var clear: float = p["r"] + c.radius + 3.0
		if lateral.length() < clear:
			var tangent := -lateral.normalized() if lateral.length() > 0.5 else dir.orthogonal()
			var w: float = 1.0 - ahead / 40.0
			dir = (dir * (1.0 - w) + tangent * (0.6 + w)).normalized()
	# AI only: feel along walls instead of pushing into a corner of the walk mask
	var player_driven: bool = c == leader and not autotest
	if walk_img != null and not player_driven:
		dir = _wall_follow(c, dir)
		dir = _unstick(c, dir)
	return dir * min(desired.length(), 1.0)


## AI that wants to move but hasn't gone anywhere for a while takes a short detour sideways
## (breaks the rare tug-of-war between a wall, a rock and the way it wants to go).
func _unstick(c: Combatant, dir: Vector2) -> Vector2:
	var dt := get_physics_process_delta_time()
	var det: float = c.get_meta("detour_t", 0.0)
	if det > 0.0:
		c.set_meta("detour_t", det - dt)
		return c.get_meta("detour_dir", dir)
	var p := c.global_position
	var lp: Vector2 = c.get_meta("st_pos", p)
	var st: float = c.get_meta("st_t", 0.0)
	if p.distance_to(lp) > 4.0:
		c.set_meta("st_pos", p)
		st = 0.0
	else:
		st += dt
	if st > 0.9:
		st = 0.0
		var side: float = [1.0, -1.0].pick_random()
		for a in [PI / 2.0, PI * 0.75, PI / 3.0, PI]:
			for sd in [side, -side]:
				var d := dir.rotated(a * sd)
				if is_walkable(p + d * 14.0, c.radius) and is_walkable(p + d * 28.0, c.radius):
					c.set_meta("detour_dir", d)
					c.set_meta("detour_t", 0.7)
					c.set_meta("st_t", 0.0)
					return d
	c.set_meta("st_t", st)
	return dir


## Probe ahead; if the way is blocked, turn (keeping to one side) until it is open.
func _wall_follow(c: Combatant, dir: Vector2) -> Vector2:
	var p := c.global_position
	if is_walkable(p + dir * 12.0, c.radius) and is_walkable(p + dir * 24.0, c.radius):
		c.set_meta("wall_side", 0)
		return dir
	var side: int = c.get_meta("wall_side", 0)
	var sides := [side] if side != 0 else [1, -1]
	for a in [0.45, 0.8, 1.15, 1.5, 1.9, 2.3]:
		for sd in sides:
			var d := dir.rotated(a * sd)
			if is_walkable(p + d * 12.0, c.radius) and is_walkable(p + d * 24.0, c.radius):
				c.set_meta("wall_side", sd)
				return d
	if side != 0:
		c.set_meta("wall_side", -side)
	return dir



func note_leader_target(h: Hero, t: Combatant) -> void:
	if h == leader and t is Enemy:
		focus_target = t


func player_aim_point() -> Vector2:
	return get_global_mouse_position()


func player_aim(h: Hero) -> Vector2:
	if using_mouse:
		var v := get_global_mouse_position() - (h.global_position + Vector2(0, -h.radius))
		return v.normalized() if v.length() > 2.0 else h.facing
	var stick := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.3:
		return rs.normalized()
	# soft auto-aim at the nearest enemy in front
	var best: Combatant = null
	var bd := 90.0
	for e in enemies:
		if e.is_dead():
			continue
		var to: Vector2 = e.global_position - h.global_position
		if to.length() < bd and to.normalized().dot(h.facing) > 0.5:
			bd = to.length()
			best = e
	if best != null:
		return (best.global_position - h.global_position).normalized()
	return h.facing if stick == Vector2.ZERO else h.facing


# =====================================================================
# Effects
# =====================================================================

func spawn_projectile(shooter: Combatant, pos: Vector2, dir: Vector2, spd: float, a: Dictionary, col: Color) -> Node:
	Sfx.play("bolt" if shooter.team != "hero" else ("bow" if spd >= 300.0 else "swing"), pos, -5.0)
	var p := Node2D.new()
	p.set_script(load("res://scripts/projectile.gd"))
	p.main = self
	p.shooter = shooter
	p.position = pos
	p.dir = dir.normalized()
	p.speed = spd
	p.action = a
	p.color = col
	p.boomerang = a.get("boomerang", false)
	p.pierce = a.get("pierce", false)
	p.z_index = 5
	world.add_child(p)
	if shooter.team != "hero":
		enemy_shots.append(p)
	return p


## What a hero should do about incoming harm right now:
## {"dir": Vector2, "dash": bool} (dir is zero when nothing threatens c).
## reaction: how early (seconds before impact) this hero notices a telegraph.
func threat_dodge(c: Combatant, reaction: float) -> Dictionary:
	var pos := c.global_position
	# telegraphed blows about to land
	for e in enemies:
		if e.is_dead() or e.state != Combatant.State.WINDUP or e.action_timer > reaction:
			continue
		var a: Dictionary = e.action
		if not a.get("is_attack", true) and a.get("shape", "") != "circle":
			continue
		if a.get("custom") != null and a.get("shape") == "line" and not a.get("dodge_line", false):
			continue  # a bolt about to be fired: handled as a projectile below
		if not in_area(e, a, c):
			continue
		var d := Vector2.ZERO
		match a.get("shape", "arc"):
			"line":
				var n: Vector2 = e.facing.orthogonal()
				d = n * (1.0 if (pos - e.global_position).dot(n) >= 0.0 else -1.0)
			"circle":
				d = (pos - a.get("_point", e.global_position)).normalized()
			_:
				var away: Vector2 = (pos - e.global_position).normalized()
				d = (away + e.facing.orthogonal() * (0.6 if randf() < 0.5 else -0.6)).normalized()
		return {"dir": _safe_dir(pos, d), "dash": true}
	# falling embers
	for em in embers:
		if is_instance_valid(em) and not em.landed and em.fuse - em.age < reaction + 0.25 and pos.distance_to(em.global_position) < em.radius + c.radius + 4.0:
			return {"dir": _safe_dir(pos, (pos - em.global_position).normalized()), "dash": true}
	# bolts and shards in flight
	for p in enemy_shots.duplicate():
		if not is_instance_valid(p):
			enemy_shots.erase(p)
			continue
		var rel: Vector2 = pos - p.global_position
		var along: float = rel.dot(p.dir)
		if along > 0.0 and along < 70.0 and absf(rel.dot(p.dir.orthogonal())) < c.radius + 5.0:
			var side: Vector2 = p.dir.orthogonal() * (1.0 if rel.dot(p.dir.orthogonal()) >= 0.0 else -1.0)
			return {"dir": _safe_dir(pos, side), "dash": along < 40.0}
	# standing in fire or moth dust: walk out
	for cl in world.get_children():
		if cl.get("kind") in ["Fire", "Dust"] and cl.get("caster") != null and is_instance_valid(cl.caster) and cl.caster.team != c.team:
			if pos.distance_to(cl.global_position) < cl.radius + c.radius:
				return {"dir": _safe_dir(pos, (pos - cl.global_position).normalized()), "dash": false}
	return {"dir": Vector2.ZERO, "dash": false}


## A dodge direction that doesn't run into the forest: try d, then turn until there's room.
func _safe_dir(pos: Vector2, d: Vector2) -> Vector2:
	if d == Vector2.ZERO:
		d = Vector2.RIGHT.rotated(randf() * TAU)
	for k in [0.0, 0.6, -0.6, 1.2, -1.2, PI]:
		var t: Vector2 = d.rotated(k)
		if is_walkable(pos + t * 40.0, 6.0):
			return t
	return d


func spawn_cloud(caster: Combatant, pos: Vector2, r: float, dur: float, kind: String, dc: int) -> void:
	Sfx.play("cast" if kind == "Silence" else "smoke", pos, -3.0)
	var c := Node2D.new()
	c.set_script(load("res://scripts/cloud.gd"))
	c.main = self
	c.caster = caster
	c.position = pos
	c.radius = r
	c.duration = dur
	c.kind = kind
	c.dc = dc
	c.z_index = 4
	world.add_child(c)


## A falling ember (Ashmaw): a red circle fills for `fuse` seconds, then it lands and burns.
func spawn_ember(caster: Combatant, pos: Vector2, r: float, fuse: float, dc: int) -> void:
	var c := Node2D.new()
	c.set_script(load("res://scripts/cloud.gd"))
	c.main = self
	c.caster = caster
	c.position = pos
	c.radius = r
	c.fuse = fuse
	c.duration = fuse + 3.0
	c.kind = "Ember"
	c.dc = dc
	c.z_index = 4
	world.add_child(c)
	embers.append(c)


## Bosses call in help: mirror images, shade moths. Minions join the encounter.
func spawn_minion(kind: String, pos: Vector2, boss: Combatant) -> Combatant:
	var e := Enemy.new()
	e.main = self
	e.setup(kind)
	e.position = pos if is_walkable(pos, 6.0) else boss.global_position
	e.home = boss.home
	e.summoner = boss
	actors.add_child(e)
	enemies.append(e)
	if active_area != "":
		area_enemies[active_area].append(e)
	boss.minions.append(e)
	return e


func float_text(pos: Vector2, text: String, col: Color, life: float = 0.8) -> void:
	var t := Node2D.new()
	t.set_script(load("res://scripts/ftext.gd"))
	t.text = text
	t.color = col
	t.life = life
	t.size = 7 if text.length() > 14 else 8
	t.position = pos
	fx.add_child(t)


func ring(pos: Vector2, r: float, col: Color) -> void:
	var n := Node2D.new()
	n.position = pos
	fx.add_child(n)
	var data := {"t": 0.0}
	n.draw.connect(func() -> void:
		var k: float = data["t"] / 0.4
		n.draw_arc(Vector2.ZERO, r * (0.3 + 0.7 * k), 0, TAU, 40, Color(col.r, col.g, col.b, 1.0 - k), 1.0))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		data["t"] = v
		n.queue_redraw(), 0.0, 0.4, 0.4)
	tw.tween_callback(n.queue_free)


## A painted effect that pops in, grows a little and fades. size = width in world px.
## opts: ground (under actors), rot, spin, grow, tint, hold (fraction of life at full alpha)
func fx_sprite(name: String, pos: Vector2, size: float, life: float, opts: Dictionary = {}) -> void:
	var t := Art.fx(name)
	if t == null:
		return
	var sp := Sprite2D.new()
	sp.texture = t
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sp.position = pos
	sp.rotation = float(opts.get("rot", 0.0))
	var base := size / t.get_size().x
	var grow: float = opts.get("grow", 0.25)
	sp.scale = Vector2.ONE * base * (1.0 - grow)
	sp.modulate = opts.get("tint", Color(1, 1, 1))
	if opts.get("ground", false):
		decal_node.add_child(sp)
	else:
		fx.add_child(sp)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * base, life * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if opts.has("spin"):
		tw.tween_property(sp, "rotation", sp.rotation + float(opts["spin"]), life)
	var hold: float = opts.get("hold", 0.45)
	tw.tween_property(sp, "modulate:a", 0.0, life * (1.0 - hold)).set_delay(life * hold)
	tw.chain().tween_callback(sp.queue_free)


func zap(a: Vector2, b: Vector2) -> void:
	var n := Node2D.new()
	fx.add_child(n)
	n.draw.connect(func() -> void:
		var pts := PackedVector2Array([a])
		for i in range(1, 5):
			pts.append(a.lerp(b, i / 5.0) + Vector2(randf_range(-4, 4), randf_range(-4, 4)))
		pts.append(b)
		n.draw_polyline(pts, Color(0.7, 0.85, 1.0), 1.0))
	get_tree().create_timer(0.12).timeout.connect(n.queue_free)


func _burst(pos: Vector2, amount: int, col_a: Color, col_b: Color, speed: float, grav: float, life: float, dir: Vector2 = Vector2.ZERO, spread: float = 180.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = dir if dir != Vector2.ZERO else Vector2.UP
	p.spread = spread
	p.gravity = Vector2(0, grav)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	var g := Gradient.new()
	g.set_color(0, col_a)
	g.set_color(1, col_b)
	p.color_ramp = g
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.8
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)


func spark(pos: Vector2, result: String, push: Vector2) -> void:
	if result == "graze":
		_burst(pos, 4, Color(0.8, 0.8, 0.7, 0.9), Color(0.5, 0.5, 0.5, 0.0), 50.0, 0.0, 0.2)
		return
	var hot := result == "crit"
	var ang := push.angle() if push != Vector2.ZERO else randf() * TAU
	fx_sprite("slash", pos, 26.0 if hot else 18.0, 0.18, {"rot": ang + randf_range(-0.4, 0.4), "grow": 0.4, "hold": 0.2})
	_burst(pos, 10 if hot else 6, Color(1.0, 0.95, 0.7) if hot else Color(1, 1, 0.9), Color(1.0, 0.5, 0.1, 0.0), 120.0 if hot else 80.0, 0.0, 0.18)
	_burst(pos, 12 if hot else 7, Color(0.7, 0.03, 0.03), Color(0.35, 0.0, 0.0, 0.0), 70.0, 220.0, 0.5, push.normalized() if push != Vector2.ZERO else Vector2.UP, 50.0)


func dust(pos: Vector2) -> void:
	_burst(pos, 8, Color(0.55, 0.5, 0.42, 0.6), Color(0.4, 0.37, 0.32, 0.0), 30.0, -10.0, 0.45)


func blood(pos: Vector2, n: int) -> void:
	# painted splats: a splash for hits, a pool for deaths
	if Art.fx("blood_splat") != null and n >= 8:
		var big := n >= 20
		blood_decals.append([pos + Vector2(randf_range(-4, 4), randf_range(-2, 3)), "blood_pool" if big else "blood_splat", randf_range(26.0, 34.0) if big else randf_range(12.0, 18.0), randf_range(-0.5, 0.5) if big else randf() * TAU])
		if blood_decals.size() > 140:
			blood_decals.pop_front()
		n = n / 3
	for i in n:
		decals.append([pos + Vector2(randf_range(-10, 10), randf_range(-5, 6)), randf_range(0.6, 2.2), randf_range(0.25, 0.5)])
	if decals.size() > 900:
		decals = decals.slice(decals.size() - 900)
	decal_node.queue_redraw()


func shake(amount: float) -> void:
	if not Settings.screen_shake:
		return
	shake_amt = max(shake_amt, amount)


func hitstop(duration: float) -> void:
	if autotest or not Settings.hit_stop:
		return
	JuiceLite.hitstop(duration, 0.05)


## Camera shake through JuiceLite, tuned down for the 480x270 viewport.
func hit_shake(amount: float) -> void:
	if autotest or amount <= 0.0 or not Settings.screen_shake:
		return
	JuiceLite.shake(amount)
	var s := camera.get_node_or_null("JuiceLiteScreenShake")
	if s != null and s.max_offset.x > 8.0:
		s.max_offset = Vector2(7.0, 5.0)
		s.max_roll = 0.012


func _on_log(text: String) -> void:
	log_lines.append(text)
	log_times.append(Time.get_ticks_msec() / 1000.0)
	if log_lines.size() > 5:
		log_lines.pop_front()
		log_times.pop_front()
	if autotest:
		print(text)



func _resource_text(h: Hero) -> String:
	match h.hero_id:
		"average": return "   GLORY %d%%%s" % [int(h.glory), "  RAGING" if h.has("raging") else ""]
		"puck": return "   herbs %d  [%s]%s" % [h.herbs, Hero.HERBS[h.herb_index], "  HAZE" if h.has("haze") else ""]
		"brokk": return "   arcane pool %d  [%s arrow]  grudges %d" % [h.arcane_pool, Hero.SPELLS[h.spell_index], h.grudges.size()]
		"sael": return "   spell slots %d" % h.slots
	return ""


func _ability_text(h: Hero) -> String:
	var names: Dictionary = {
		"average": ["1 Rage", "2 Look At Me!", "Q Ground Slam"],
		"puck": ["1 Next herb", "2 Pass it around", "3 Haze", "Q Burn herb"],
		"brokk": ["1 Next spell", "2 Dwarven Stand", "3 Many Shot", "Q Spell arrow"],
		"sael": ["1 Silence", "2 Break the Chains", "3 Breath of Life", "Q Channel heal"],
	}
	var cd_keys := {"Rage": "rage", "Ground Slam": "slam", "Haze": "haze", "Pass it around": "share", "Dwarven Stand": "stand", "Many Shot": "many", "Silence": "silence", "Break the Chains": "chains"}
	var parts := []
	for n in names[h.hero_id]:
		var label: String = n
		for k in cd_keys:
			if label.ends_with(k) and h.cd(cd_keys[k]) > 0.0:
				label += " (%d)" % int(ceil(h.cd(cd_keys[k])))
		parts.append(label)
	return "  ".join(parts)




# =====================================================================
# Drawing: decals and HUD
# =====================================================================

func _draw_decals() -> void:
	for d in blood_decals:
		var t := Art.fx(d[1])
		var k: float = float(d[2]) / t.get_size().x
		decal_node.draw_set_transform(d[0], d[3], Vector2(k, k * 0.7))
		decal_node.draw_texture(t, -t.get_size() / 2.0, Color(0.85, 0.85, 0.85, 0.85))
	decal_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d in decals:
		decal_node.draw_rect(Rect2(d[0], Vector2(d[1] * 1.6, d[1])), Color(d[2] + 0.2, 0.02, 0.02, 0.9))


func _portrait_big(id: String, dest: Rect2, dead: bool) -> void:
	var pf := Art.portrait_framed(id)
	if pf == null:
		_portrait(id, dest, dead)
		return
	hud.draw_texture_rect(pf, dest, false, Color(0.4, 0.33, 0.33) if dead else Color(1, 1, 1))


func _portrait(id: String, dest: Rect2, dead: bool) -> void:
	var pt := Art.portrait(id)
	if pt != null:
		hud.draw_texture_rect(pt, dest, false, Color(0.35, 0.3, 0.3) if dead else Color(1, 1, 1))
		return
	var meta: Dictionary = Art.manifest["characters"][id]
	var fw: float = meta["frame_w"]
	var fh: float = meta["frame_h"]
	var fy: float = meta.get("foot_y", fh)
	var k: float = 0.5 / float(meta.get("scale", 0.5))
	var head_h: float = {"average": 64.0, "puck": 56.0, "brokk": 50.0, "sael": 56.0}.get(id, 56.0) * k
	var src := Rect2(fw / 2.0 - 15.0 * k, fy - head_h - 4.0 * k, 30.0 * k, 30.0 * k)
	hud.draw_texture_rect_region(Art.tex(id), dest, src, Color(0.35, 0.35, 0.35) if dead else Color(1, 1, 1))


func _panel(r: Rect2, alpha: float = 0.88) -> void:
	hud.draw_rect(r, Color(0.05, 0.045, 0.05, alpha))
	hud.draw_rect(r, Color(0.32, 0.27, 0.2), false, 1.0)
	hud.draw_rect(r.grow(-2), Color(0.16, 0.13, 0.1), false, 1.0)


func _text(pos: Vector2, s: String, size: int, col: Color, outline: bool = false) -> void:
	var f := ThemeDB.fallback_font
	if outline:
		hud.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a))
	hud.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(cx: float, y: float, s: String, size: int, col: Color, outline: bool = true) -> void:
	var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(Vector2(cx - w / 2.0, y), s, size, col, outline)


# =====================================================================
# Menus (title, pause, options, controls, credits)
# =====================================================================

const MENU_ITEMS := {
	"title": ["Begin", "Options", "Controls", "Credits", "Quit"],
	"pause": ["Resume", "The Party", "Options", "Controls", "Credits", "Quit to title"],
}
const CD_MAX := {"rage": 30.0, "slam": 7.0, "share": 4.0, "haze": 30.0, "stand": 18.0, "many": 12.0, "silence": 12.0, "chains": 10.0}

var menu_i := 0
var blood_decals: Array = []      # [pos, texture name, width, rotation]
var menu_frame := -1             # frame a menu consumed input (stops Esc closing and reopening)
var menu_back := "title"         # where options/controls/credits return to
var hp_lag := 1.0
var lag_hero: Hero = null
var log_times: Array = []


func set_ui(s: String) -> void:
	if s == "inventory" and inv != null:
		inv.open()
	ui = s
	menu_i = 0
	if s == "play":
		started = true
	if not autotest:
		var menu_from_title := s in ["options", "controls", "credits"] and menu_back == "title"
		get_tree().paused = s in ["pause", "options", "controls", "credits", "inventory", "level", "talk", "shop"] and not menu_from_title


func _menu_list() -> Array:
	if ui == "options":
		return [
			"Fullscreen: " + ("on" if Settings.fullscreen else "off"),
			"Screen shake: " + ("on" if Settings.screen_shake else "off"),
			"Hit-stop: " + ("on" if Settings.hit_stop else "off"),
			"Hit flash: " + ("on" if Settings.hit_flash else "off"),
			"Dice rolls on screen: " + ("on" if Settings.dice_log else "off"),
			"Hints: " + ("on" if Settings.hints else "off"),
			"Music volume: %d%%" % int(round(Settings.music_volume * 100)),
			"Sound volume: %d%%" % int(round(Settings.sfx_volume * 100)),
			"Back",
		]
	if ui == "title":
		var t: Array = ["Continue", "New game", "Options", "Controls", "Credits", "Quit"] if Run.has_save() else MENU_ITEMS["title"].duplicate()
		return t + _test_levels()
	return MENU_ITEMS.get(ui, ["Back"])


## Where the menu sits: DorkTeach's candle panel for pause and options, loose bars on the title.
func _menu_layout() -> Dictionary:
	var n: int = max(1, _menu_list().size())
	var pt: Texture2D = Art.ui("menu_panel")
	if pt != null and ui in ["pause", "options"]:
		var pw := 226.0 if ui == "pause" else 300.0
		var ph := pw * float(pt.get_height()) / float(pt.get_width())
		var pr := Rect2(240.0 - pw / 2.0, 18.0 if ui == "options" else 40.0, pw, ph)
		var fr: Array = Art.ui_info("menu_panel").get("inner", [0.13, 0.34, 0.92, 0.9])
		var inner := Rect2(pr.position + Vector2(fr[0], fr[1]) * pr.size, Vector2(fr[2] - fr[0], fr[3] - fr[1]) * pr.size)
		var step: float = min(20.0, (inner.size.y - 4.0) / n)
		return {"panel": pr, "x": inner.position.x + 6.0, "w": inner.size.x - 12.0, "y0": inner.position.y + 2.0, "step": step}
	var y0: float = {"title": 140.0, "pause": 92.0, "options": 70.0}.get(ui, 252.0)
	var st: float = 15.0 if ui != "title" else min(15.0, 118.0 / n)
	return {"panel": Rect2(), "x": 240.0 - 80.0, "w": 160.0, "y0": y0, "step": st}


func _menu_y0() -> float:
	var lay := _menu_layout()
	return lay["y0"] + lay["step"] * 0.5 + 3.0


func _menu_rect(i: int) -> Rect2:
	var lay := _menu_layout()
	return Rect2(lay["x"], lay["y0"] + i * lay["step"], lay["w"], lay["step"] - 2.0)


func _menu_confirm() -> void:
	var items := _menu_list()
	var item: String = items[clamp(menu_i, 0, items.size() - 1)]
	match ui:
		"title":
			match item:
				"Begin", "New game": set_ui("select")
				"Continue":
					if Run.load_game():
						get_tree().reload_current_scene()
				"Quit": get_tree().quit()
				_ when item.begins_with("Try: "):
					Run.reset()
					Run.level_override = item.substr(5)
					get_tree().reload_current_scene()
				_:
					menu_back = "title"
					set_ui(item.to_lower())
		"pause":
			match item:
				"Resume": set_ui("play")
				"The Party": set_ui("inventory")
				"Quit to title":
					save_now()
					get_tree().paused = false
					Run.reset()
					get_tree().reload_current_scene()
				_:
					menu_back = "pause"
					set_ui(item.to_lower())
		"options":
			match menu_i:
				0:
					Settings.fullscreen = not Settings.fullscreen
					Settings.apply_video()
				1: Settings.screen_shake = not Settings.screen_shake
				2: Settings.hit_stop = not Settings.hit_stop
				3: Settings.hit_flash = not Settings.hit_flash
				4: Settings.dice_log = not Settings.dice_log
				5: Settings.hints = not Settings.hints
				6:
					Settings.music_volume = 0.0 if Settings.music_volume >= 0.99 else min(1.0, Settings.music_volume + 0.25)
					Sfx.apply_volumes()
				7:
					Settings.sfx_volume = 0.0 if Settings.sfx_volume >= 0.99 else min(1.0, Settings.sfx_volume + 0.25)
					Sfx.apply_volumes()
				_:
					Settings.save()
					_menu_back()
					return
			Settings.save()
		_:
			_menu_back()


func _menu_back() -> void:
	match ui:
		"options", "controls", "credits":
			if ending and ui == "credits":
				get_tree().paused = false
				Run.reset()
				get_tree().reload_current_scene()
				return
			var came_from: String = ui.capitalize()
			set_ui(menu_back)
			menu_i = max(0, _menu_list().find(came_from))
		"pause":
			set_ui("play")


func _menu_input(event: InputEvent) -> void:
	var items := _menu_list()
	if event is InputEventMouseMotion:
		for i in items.size():
			if _menu_rect(i).has_point(hud.get_local_mouse_position()):
				menu_i = i
		return
	var pressed: bool = (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	menu_frame = Engine.get_process_frames()
	var key: int = event.physical_keycode if event is InputEventKey else -1
	var pad: int = event.button_index if event is InputEventJoypadButton else -1
	if key in [KEY_W, KEY_UP] or pad == JOY_BUTTON_DPAD_UP:
		menu_i = (menu_i + items.size() - 1) % items.size()
		Sfx.play("ui_move", null, -4.0, 0.0)
	elif key in [KEY_S, KEY_DOWN] or pad == JOY_BUTTON_DPAD_DOWN:
		menu_i = (menu_i + 1) % items.size()
		Sfx.play("ui_move", null, -4.0, 0.0)
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F] or pad == JOY_BUTTON_A:
		Sfx.play("ui_confirm", null, -3.0, 0.0)
		_menu_confirm()
	elif key == KEY_ESCAPE or pad in [JOY_BUTTON_B, JOY_BUTTON_START]:
		Sfx.play("ui_back", null, -3.0, 0.0)
		_menu_back()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		for i in items.size():
			if _menu_rect(i).has_point(hud.get_local_mouse_position()):
				menu_i = i
				Sfx.play("ui_confirm", null, -3.0, 0.0)
				_menu_confirm()
				return
		if ui in ["controls", "credits"]:
			_menu_back()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_menu_back()


func _draw_menu_items(col_dim: Color = Color(0.62, 0.58, 0.52)) -> void:
	var items := _menu_list()
	var lay := _menu_layout()
	var pr: Rect2 = lay["panel"]
	if pr.size.x > 0.0:
		hud.draw_texture_rect(Art.ui("menu_panel"), pr, false)
	var bar_t: Texture2D = Art.ui("menu_bar")
	for i in items.size():
		var r := _menu_rect(i)
		var sel := i == menu_i
		var y := r.get_center().y + 3.0
		if bar_t != null:
			hud.draw_texture_rect(bar_t, r, false, Color(1.08, 1.0, 0.92) if sel else Color(0.55, 0.52, 0.5))
		elif sel:
			hud.draw_rect(r, Color(0.35, 0.22, 0.1, 0.35))
		if sel:
			hud.draw_rect(r.grow(1), Color(0.95, 0.75, 0.38, 0.9), false, 1.0)
			_moth(Vector2(r.position.x + 10, y - 3), Color(0.95, 0.8, 0.45))
			_moth(Vector2(r.end.x - 10, y - 3), Color(0.95, 0.8, 0.45))
		var label: String = items[i]
		var size := 9 if r.size.y >= 13.0 else 8
		if ui == "options" and ": " in label:
			# label on the left, a checkbox or a slider on the right
			var parts := label.split(": ")
			_text(Vector2(r.position.x + 18, y), parts[0], 8, Color(0.98, 0.9, 0.7) if sel else col_dim.lightened(0.1), true)
			var val: String = parts[1]
			if val.ends_with("%"):
				var tr: Texture2D = Art.ui("slider_track")
				var sr := Rect2(r.end.x - 98, r.get_center().y - 5, 78, 10)
				if tr != null:
					hud.draw_texture_rect(tr, sr, false)
				var f: float = float(val.trim_suffix("%")) / 100.0
				var kt: Texture2D = Art.ui("slider_knob")
				var kx := sr.position.x + 6 + (sr.size.x - 12) * f
				if kt != null:
					hud.draw_texture_rect(kt, Rect2(kx - 4, sr.position.y - 3, 8, 16), false)
				_text(Vector2(r.end.x - 16, y), "%d" % int(f * 100), 6, Color(0.8, 0.76, 0.68), true)
			else:
				var ct: Texture2D = Art.ui("check_on" if val == "on" else "check_off")
				var cr := Rect2(r.end.x - 30, r.get_center().y - 6, 12, 12)
				if ct != null:
					hud.draw_texture_rect(ct, cr, false)
				else:
					_text(Vector2(cr.position.x, y), val, 8, col_dim, true)
			continue
		_text_c(r.get_center().x, y, label, size, Color(0.98, 0.9, 0.7) if sel else col_dim.lightened(0.1))


func _moth(c: Vector2, col: Color) -> void:
	hud.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1), c + Vector2(-4, -3), c + Vector2(-3, 1), c + Vector2(0, 2), c + Vector2(3, 1), c + Vector2(4, -3)]), col)


func _dim(a: float = 0.6) -> void:
	hud.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.0, 0.01, a))


func _draw_title() -> void:
	_dim(0.5)
	hud.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.0))
	var t := Time.get_ticks_msec() / 1000.0
	_moth(Vector2(240, 70 + sin(t * 1.3) * 2.0), Color(0.75, 0.72, 0.9, 0.8))
	_text_c(240, 104, "HOLLOWMOTH", 34, Color(0.88, 0.8, 0.62))
	_text_c(240, 120, "The stars are going out, one by one.", 8, Color(0.7, 0.68, 0.62))
	_draw_menu_items()
	if Run.has_save():
		_text_c(240, 132, "Saved: " + Run.save_info(), 7, Color(0.62, 0.66, 0.78))
	_text_c(240, 262, "a game by DorkTeach", 7, Color(0.5, 0.48, 0.44))


func _draw_pause() -> void:
	_dim(0.65)
	_draw_menu_items()
	_text_c(240, 30, "PAUSED", 18, Color(0.88, 0.8, 0.62))
	_text_c(240, 254, "%s  -  %s, level %d" % [L.get("subtitle", Run.ACT_NAMES[clamp(Run.act, 1, Run.LAST_ACT)]), leader.display_name, leader.level], 7, Color(0.6, 0.58, 0.54))


func _draw_options() -> void:
	_dim(0.75)
	_draw_menu_items()
	_text_c(240, 14, "OPTIONS", 12, Color(0.88, 0.8, 0.62))
	var notes := ["F11 also toggles fullscreen.", "Shakes the camera on heavy hits.", "A short freeze on crits and parries.",
		"Enemies flash white when you hit them.", "Shows every d20 roll, Pathfinder style.", "Button prompts near shrines and gates.", "Music: 0, 25, 50, 75 or 100%.", "Sound effects and ambience.", ""]
	_text_c(240, 266, notes[clamp(menu_i, 0, notes.size() - 1)] + "     Enter: change   Esc: back", 6, Color(0.62, 0.62, 0.64))


func _draw_controls() -> void:
	_dim(0.8)
	_text_c(240, 34, "CONTROLS", 16, Color(0.88, 0.8, 0.62))
	var rows := [
		["Move", "WASD", "Left stick"],
		["Aim", "Mouse", "Right stick"],
		["Attack", "Left mouse / J", "X"],
		["Special", "Right mouse / K", "Y"],
		["Cast", "Q", "Right trigger"],
		["Dash (i-frames)", "Space", "A"],
		["Parry / block", "Shift", "Left bumper"],
		["Abilities", "1  2  3", "-"],
		["Drink a draught", "E", "B"],
		["Interact / rest", "F", "Back"],
		["Party & gear", "I", "Pause menu"],
		["Level up (at shrine)", "L", "-"],
		["Pause", "Esc", "Start"],
	]
	_text(Vector2(80, 54), "ACTION", 7, Color(0.75, 0.6, 0.35))
	_text(Vector2(220, 54), "KEYBOARD", 7, Color(0.75, 0.6, 0.35))
	_text(Vector2(330, 54), "GAMEPAD", 7, Color(0.75, 0.6, 0.35))
	for i in rows.size():
		var y := 68.0 + i * 12.0
		_text(Vector2(80, y), rows[i][0], 8, Color(0.88, 0.84, 0.76))
		_text(Vector2(220, y), rows[i][1], 8, Color(0.95, 0.85, 0.6))
		_text(Vector2(330, y), rows[i][2], 8, Color(0.7, 0.7, 0.72))
	_text_c(240, 232, "Your companions fight on their own. Parry right before a hit lands to open a riposte.", 6, Color(0.6, 0.6, 0.62))
	_draw_menu_items()


func _draw_credits() -> void:
	_dim(0.85)
	_text_c(240, 46, "HOLLOWMOTH", 20, Color(0.88, 0.8, 0.62))
	var lines := [
		["A game by", "DorkTeach"],
		["Design, story and heroes", "DorkTeach"],
		["Engine", "Godot Engine 4.7 (MIT)"],
		["Hit feedback", "Sprite Juice Kit Lite - REEBOO Labs (MIT)"],
		["Art", "Procedural pixel art made for this project"],
		["Rules", "A d20 system inspired by Pathfinder 1e"],
		["Built with", "Claude"],
	]
	for i in lines.size():
		var y := 76.0 + i * 20.0
		_text_c(240, y, lines[i][0], 7, Color(0.6, 0.56, 0.5))
		_text_c(240, y + 10, lines[i][1], 9, Color(0.92, 0.86, 0.74))
	_draw_menu_items()


# =====================================================================
# In-game HUD
# =====================================================================

func _bar(r: Rect2, frac: float, col: Color, lag: float = -1.0) -> void:
	hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.85))
	hud.draw_rect(r, Color(0.08, 0.06, 0.05))
	if lag > frac:
		hud.draw_rect(Rect2(r.position, Vector2(r.size.x * lag, r.size.y)), Color(0.95, 0.78, 0.45))
	hud.draw_rect(Rect2(r.position, Vector2(r.size.x * clamp(frac, 0.0, 1.0), r.size.y)), col)
	hud.draw_rect(Rect2(r.position, Vector2(r.size.x * clamp(frac, 0.0, 1.0), 1)), col.lightened(0.3))
	hud.draw_rect(r.grow(1), Color(0.42, 0.34, 0.24), false, 1.0)


func _slots(h: Hero) -> Array:
	# [key, label, cooldown key or "", usable, icon]
	match h.hero_id:
		"average":
			return [["Q", "Slam", "slam", true, "slam"], ["1", "Rage", "rage", true, "rage"], ["2", "Taunt", "", h.glory >= 100.0, "taunt"]]
		"puck":
			var herb: String = Hero.HERBS[h.herb_index]
			return [["Q", "Burn", "", h.herbs > 0, "burn"], ["1", herb.substr(0, 6), "", true, herb.to_lower()], ["2", "Share", "share", h.herbs > 0, "share"], ["3", "Haze", "haze", true, "haze"]]
		"brokk":
			var sp: String = Hero.SPELLS[h.spell_index]
			return [["Q", sp, "", h.arcane_pool > 0, sp.to_lower()], ["1", "Swap", "", true, "swap"], ["2", "Stand", "stand", true, "stand"], ["3", "Many", "many", true, "many"]]
		"sael":
			return [["Q", "Heal", "", h.slots > 0, "heal"], ["1", "Silence", "silence", true, "silence"], ["2", "Chains", "chains", true, "chains"], ["3", "Revive", "", h.slots > 0, "revive"]]
	return []


const STATUS_ICONS := {
	"buff": ["raging", "taunting", "sunthistle", "haze", "dreamleaf_share", "gigglecap"],
	"guard": ["ward", "stand"],
	"haste": ["slowed", "prone", "staggered"],
	"wound": ["fatigued", "nauseated", "confused", "silenced", "asleep", "parried"],
}


## An orb that drains: glass, liquid clipped to the fill level, a surface line, shine, frame.
func _orb(kind: String, r: Rect2, frac: float, lag: float = -1.0) -> void:
	var m := Art.ui_info("orb_" + kind)
	if m.is_empty():
		return
	var sz := Vector2(m["size"][0], m["size"][1])
	var k := r.size.x / sz.x
	hud.draw_texture_rect(Art.ui("orb_%s_glass" % kind), r, false)
	var cy: float = m["cy"]
	var rad: float = m["r"]
	frac = clamp(frac, 0.0, 1.0)
	if lag > frac:
		var lt := cy + rad - 2.0 * rad * lag
		hud.draw_texture_rect_region(Art.ui("orb_%s_liquid" % kind), Rect2(r.position + Vector2(0, lt * k), Vector2(r.size.x, (sz.y - lt) * k)), Rect2(0, lt, sz.x, sz.y - lt), Color(1.6, 1.4, 1.2, 0.55))
	var top := cy + rad - 2.0 * rad * frac
	if frac > 0.0:
		hud.draw_texture_rect_region(Art.ui("orb_%s_liquid" % kind), Rect2(r.position + Vector2(0, top * k), Vector2(r.size.x, (sz.y - top) * k)), Rect2(0, top, sz.x, sz.y - top))
		if frac < 0.98:
			var dy := top - cy
			var half := sqrt(max(0.0, rad * rad - dy * dy)) - 1.0
			var cx: float = m["cx"]
			var y := r.position.y + top * k
			hud.draw_line(Vector2(r.position.x + (cx - half) * k, y), Vector2(r.position.x + (cx + half) * k, y), Color(1, 0.85, 0.7, 0.55), 0.5)
	hud.draw_texture_rect(Art.ui("orb_%s_shine" % kind), r, false)
	hud.draw_texture_rect(Art.ui("orb_%s_frame" % kind), r, false)


## A framed bar (boss or companion) with its interior filled from the left.
func _framed_bar(kind: String, r: Rect2, frac: float) -> void:
	var m := Art.ui_info("bar_" + kind)
	if m.is_empty():
		return
	var sz := Vector2(m["size"][0], m["size"][1])
	var k := r.size.x / sz.x
	var it: Array = m["interior"]
	var inner := Rect2(r.position + Vector2(it[0], it[1]) * k, Vector2(it[2], it[3]) * k)
	hud.draw_rect(inner, Color(0.07, 0.04, 0.045))
	var f: float = clamp(frac, 0.0, 1.0)
	if f > 0.0:
		var fill := Art.ui("bar_%s_fill" % kind)
		hud.draw_texture_rect(fill, Rect2(inner.position, Vector2(inner.size.x * f, inner.size.y)), false)
	hud.draw_texture_rect(Art.ui("bar_%s_frame" % kind), r, false)


## A portrait clipped to a circle (for the companion bar's socket).
func _round_portrait(id: String, c: Vector2, rad: float, dead: bool) -> void:
	var t := Art.portrait(id)
	if t == null:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var col := Color(0.4, 0.33, 0.33) if dead else Color(1, 1, 1)
	for i in 24:
		var a := TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * rad)
		uvs.append(Vector2(0.5, 0.45) + d * 0.42)
		cols.append(col)
	hud.draw_polygon(pts, cols, uvs, t)


func _ui_panel(r: Rect2) -> void:
	var t := Art.ui("panel")
	if t == null:
		_panel(r, 0.85)
		return
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 44
	sb.texture_margin_bottom = 30
	# the plaque is painted at 4x HUD density: draw it in a 0.25 transform so its borders keep their size
	hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.25, 0.25))
	hud.draw_style_box(sb, Rect2(r.position * 4.0, r.size * 4.0))
	hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_play_hud() -> void:
	var W := 480.0
	var H := 270.0
	var h: Hero = leader
	var has_ui := not Art.ui_info("orb_hp").is_empty()
	if not has_ui:
		return
	# --- leader: framed portrait, name, resource, conditions (top left)
	_portrait_big(h.hero_id, Rect2(3, 3, 36, 36), h.is_dead())
	_text(Vector2(44, 12), h.display_name.to_upper(), 9, Color(0.95, 0.88, 0.7), true)
	_text(Vector2(44 + ThemeDB.fallback_font.get_string_size(h.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 5, 12), "lv %d" % h.level, 6, Color(0.7, 0.66, 0.58), true)
	var res := _resource_text(h).strip_edges()
	if res != "":
		_text(Vector2(44, 22), res, 6, Color(0.78, 0.74, 0.62), true)
	var ix := 44.0
	for kind in STATUS_ICONS:
		var best := 0.0
		for c in STATUS_ICONS[kind]:
			best = max(best, float(h.conditions.get(c, 0.0)))
		if best > 0.0:
			var tint := Color(1, 0.75, 0.7) if kind in ["haste", "wound"] else Color(1, 1, 1)
			hud.draw_texture_rect(Art.ui("status_" + kind), Rect2(ix, 26, 11, 11), false, tint)
			_text(Vector2(ix + 8, 37), str(int(ceil(best))), 5, Color(0.9, 0.88, 0.8), true)
			ix += 15.0
	# --- companions: socket + bar
	var comp := heroes.filter(func(x): return x != leader)
	var cm := Art.ui_info("bar_comp")
	var csz := Vector2(cm["size"][0], cm["size"][1])
	for i in comp.size():
		var o: Hero = comp[i]
		var r := Rect2(3, 44 + i * 26.0, 86, 86.0 * csz.y / csz.x)
		var k := r.size.x / csz.x
		_framed_bar("comp", r, 0.0 if o.is_dead() else float(o.hp) / o.max_hp)
		var sock: Array = cm["socket"]
		_round_portrait(o.hero_id, r.position + Vector2(sock[0], sock[1]) * k, float(sock[2]) * k * 0.92, o.is_dead())
		var label := o.display_name + ("  -  fallen" if o.is_dead() else "")
		_text(r.position + Vector2(21, 9), label, 6, Color(0.8, 0.25, 0.22) if o.is_dead() else Color(0.86, 0.82, 0.72), true)
	# --- orbs: HP bottom left, stamina bottom right
	var om := Art.ui_info("orb_hp")
	var osz := Vector2(om["size"][0], om["size"][1])
	var ow := 64.0
	var oh := ow * osz.y / osz.x
	var hr := Rect2(1, H - oh - 1, ow, oh)
	_orb("hp", hr, float(h.hp) / h.max_hp, hp_lag)
	_text_c(hr.get_center().x, hr.end.y - 6, "%d" % h.hp, 7, Color(1, 0.92, 0.88))
	var sr := Rect2(W - ow - 1, H - oh - 1, ow, oh)
	_orb("st", sr, h.stamina / h.max_stamina)
	# --- skill bar + draught slot (bottom centre)
	var sm := Art.ui_info("skillbar")
	var ssz := Vector2(sm["size"][0], sm["size"][1])
	var bw := 150.0
	var bk := bw / ssz.x
	var bh := ssz.y * bk
	var dm := Art.ui_info("slot_draught")
	var dsz := Vector2(dm["size"][0], dm["size"][1]) * bk
	var bx := (W - bw - dsz.x - 2.0) / 2.0
	var by := H - bh - 2.0
	hud.draw_texture_rect(Art.ui("skillbar"), Rect2(bx, by, bw, bh), false)
	var slots: Array = sm["slots"]
	var abil := _slots(h)
	for i in min(slots.size(), abil.size()):
		var sl: Array = slots[i]
		var r := Rect2(bx + float(sl[0]) * bk, by + float(sl[1]) * bk, float(sl[2]) * bk, float(sl[3]) * bk)
		var s: Array = abil[i]
		var cdk: String = s[2]
		var rem: float = h.cd(cdk) if cdk != "" else 0.0
		var ok: bool = s[3] and rem <= 0.0
		var ic: Texture2D = Art.tex("icon_skill_" + str(s[4])) if s.size() > 4 else null
		if ic != null:
			hud.draw_texture_rect(ic, r.grow(-1.0), false, Color(1, 1, 1) if ok else Color(0.4, 0.4, 0.42))
			hud.draw_rect(Rect2(r.position.x + 1, r.end.y - 7, r.size.x - 2, 6), Color(0, 0, 0, 0.55))
		if rem > 0.0:
			var f: float = clamp(rem / CD_MAX.get(cdk, 10.0), 0.0, 1.0)
			hud.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * f)), Color(0, 0, 0, 0.55))
			_text_c(r.get_center().x, r.get_center().y + 3, str(int(ceil(rem))), 8, Color(0.92, 0.9, 0.86))
		_text(r.position + Vector2(1, 6), s[0], 6, Color(0.95, 0.75, 0.35), true)
		_text_c(r.get_center().x, r.end.y - 1, s[1], 5, Color(0.92, 0.88, 0.8) if ok else Color(0.5, 0.48, 0.45), true)
	var dr := Rect2(bx + bw + 2.0, by + (bh - dsz.y) / 2.0, dsz.x, dsz.y)
	hud.draw_texture_rect(Art.ui("slot_draught"), dr, false, Color(1, 1, 1) if draughts > 0 else Color(0.45, 0.45, 0.45))
	_text(dr.position + Vector2(2, 7), "E", 6, Color(0.95, 0.75, 0.35), true)
	# draughts as candles
	for i in draught_max:
		var lit := i < draughts
		hud.draw_texture_rect(Art.ui("candle_lit" if lit else "candle_out"), Rect2(dr.end.x + 3 + i * 9.0, H - 17, 9, 13), false)
	# --- starlight (moth) above the stamina orb
	var sl_txt := "%d" % starlight
	var tw := ThemeDB.fallback_font.get_string_size(sl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	hud.draw_texture_rect(Art.ui("moth"), Rect2(W - tw - 26, H - oh - 18, 16, 16), false)
	_text(Vector2(W - tw - 7, H - oh - 6), sl_txt, 9, Color(0.9, 0.9, 1.0), true)
	# --- boss bar (top centre)
	var boss_on := false
	for e in enemies:
		if e.is_boss and not e.is_dead() and e.global_position.distance_to(h.global_position) < 260.0:
			boss_on = true
			var bm := Art.ui_info("bar_boss")
			var bsz := Vector2(bm["size"][0], bm["size"][1])
			var bbw := 250.0
			var br := Rect2((W - bbw) / 2.0, 3, bbw, bbw * bsz.y / bsz.x)
			_framed_bar("boss", br, float(e.hp) / e.max_hp)
			_text_c(W / 2, br.end.y + 7, e.display_name.to_upper(), 7, Color(0.88, 0.78, 0.62))
			break
	# --- dice log (optional, fades)
	if Settings.dice_log:
		var f := ThemeDB.fallback_font
		var now := Time.get_ticks_msec() / 1000.0
		var y0 := 46.0 if boss_on else 10.0
		for i in log_lines.size():
			var age: float = now - float(log_times[i]) if i < log_times.size() else 0.0
			var a: float = clamp(1.0 - (age - 5.0) / 2.0, 0.0, 1.0)
			if a <= 0.0:
				continue
			var line: String = log_lines[i]
			var w: float = min(f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x, 230.0)
			hud.draw_string_outline(f, Vector2(W - 4 - w, y0 + i * 8), line, HORIZONTAL_ALIGNMENT_LEFT, 230, 6, 2, Color(0, 0, 0, 0.8 * a))
			hud.draw_string(f, Vector2(W - 4 - w, y0 + i * 8), line, HORIZONTAL_ALIGNMENT_LEFT, 230, 6, Color(0.72, 0.7, 0.64, a))
	elif Settings.hints and ui == "play" and not boss_on:
		_text(Vector2(W - 44, 10), "Esc  menu", 6, Color(0.55, 0.53, 0.5, 0.8), true)
	# --- context prompt on a stone plaque
	if ui == "play" and Settings.hints:
		var p := h.global_position
		var prompt := ""
		if p.distance_to(shrine_pos) < 50.0:
			prompt = "F  rest at the Moth Shrine        L  level up"
		elif camp.prompt(p) != "":
			prompt = camp.prompt(p)
		elif not gate_open and p.distance_to(_v(L["gate"]["pos"])) < 50.0:
			prompt = "F  open the gate"
		elif Run.act < Run.LAST_ACT and boss_dead and p.distance_to(rift_pos) < 46.0:
			prompt = "F  step through the rift"
		elif not loot_bags.is_empty():
			for b in loot_bags:
				if p.distance_to(b["pos"]) < 22.0:
					prompt = "F  take " + Items.describe(b["item"], h.hero_id)
					break
		if prompt != "":
			var pw := ThemeDB.fallback_font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_ui_panel(Rect2(W / 2 - pw / 2 - 14, H - 70, pw + 28, 22))
			_text_c(W / 2, H - 55, prompt, 8, Color(0.95, 0.9, 0.8))


func _draw_hud() -> void:
	var W := 480.0
	var H := 270.0
	match ui:
		"title":
			_draw_title()
			return
		"select":
			_draw_select(W, H)
			return
		"options", "controls", "credits":
			if menu_back == "title":
				match ui:
					"options": _draw_options()
					"controls": _draw_controls()
					"credits": _draw_credits()
				return
	if ui != "talk":
		_draw_play_hud()
		banter.draw_bubbles(hud)
	# banner
	if banner_t > 0.0 and ui in ["play", "dead"]:
		var a: float = clamp(banner_t, 0.0, 1.0)
		hud.draw_rect(Rect2(0, 92, W, 44), Color(0, 0, 0, 0.45 * a))
		_text_c(W / 2, 118, banner, 15, Color(banner_col.r, banner_col.g, banner_col.b, a))
		if banner_sub != "":
			_text_c(W / 2, 131, banner_sub, 8, Color(0.75, 0.72, 0.66, a))
	match ui:
		"dead":
			hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
			_text_c(W / 2, 140, "YOU DIED", 34, Color(0.6, 0.06, 0.04))
		"level": _draw_level_menu(W, H)
		"inventory": inv.draw(W, H)
		"shop": camp.draw(W, H)
		"pause": _draw_pause()
		"talk": banter.draw_talk(hud)
		"options": _draw_options()
		"controls": _draw_controls()
		"credits": _draw_credits()


## The Moth Shrine (DorkTeach's shrine sheet): the hero's sheet on the left, the shrine's choices on the right.
var shrine_i := 0


func _shrine_rows() -> Array:
	var cost := Hero.level_cost(leader.level)
	return [["Level up  -  %d" % cost, starlight >= cost], ["Rest at the shrine", active_area == ""], ["The Party: gear & sigils", true], ["Leave the shrine", true]]


func _shrine_do(i: int) -> void:
	match i:
		0: try_level_up(leader)
		1:
			set_ui("play")
			try_rest()
		2: set_ui("inventory")
		_: set_ui("play")


func _sub(r: Rect2, f: Array) -> Rect2:
	return Rect2(r.position + Vector2(f[0], f[1]) * r.size, Vector2(f[2] - f[0], f[3] - f[1]) * r.size)


func _lvl_rects() -> Dictionary:
	var lt: Texture2D = Art.ui("lvl_panel")
	var rt: Texture2D = Art.ui("shrine_panel")
	var h := 236.0
	var lw := h * (float(lt.get_width()) / float(lt.get_height()) if lt != null else 0.89)
	var rw := h * (float(rt.get_width()) / float(rt.get_height()) if rt != null else 0.7)
	var x0 := (480.0 - lw - rw - 10.0) / 2.0
	return {"left": Rect2(x0, 17, lw, h), "right": Rect2(x0 + lw + 10.0, 17, rw, h)}


func _draw_level_menu(W: float, H: float) -> void:
	var o: Hero = leader
	_dim(0.5)
	if Art.ui("lvl_panel") == null:
		_draw_level_menu_plain(W, H)
		return
	var rr := _lvl_rects()
	var lp: Rect2 = rr["left"]
	var rp: Rect2 = rr["right"]
	var lm: Dictionary = Art.ui_info("lvl_panel")
	var rm: Dictionary = Art.ui_info("shrine_panel")
	hud.draw_texture_rect(Art.ui("lvl_panel"), lp, false)
	hud.draw_texture_rect(Art.ui("shrine_panel"), rp, false)
	# --- the hero
	var pt := Art.portrait(o.hero_id)
	if pt != null:
		hud.draw_texture_rect(pt, _sub(lp, lm["well"]).grow(-1), false)
	var cost := Hero.level_cost(o.level)
	var b1 := _sub(lp, lm["bar1"]).grow(-2)
	hud.draw_rect(Rect2(b1.position, Vector2(b1.size.x * clamp(float(o.hp) / o.max_hp, 0.0, 1.0), b1.size.y)), Color(0.62, 0.1, 0.1))
	_text_c(b1.get_center().x, b1.get_center().y + 3, "HP %d / %d" % [o.hp, o.max_hp], 6, Color(0.95, 0.9, 0.85))
	var b2 := _sub(lp, lm["bar2"]).grow(-2)
	hud.draw_rect(Rect2(b2.position, Vector2(b2.size.x * clamp(float(starlight) / cost, 0.0, 1.0), b2.size.y)), Color(0.62, 0.52, 0.22))
	_text_c(b2.get_center().x, b2.get_center().y + 3, "Starlight %d / %d" % [starlight, cost], 6, Color(0.95, 0.92, 0.8))
	# what the next level brings
	var now := {"hp": o.max_hp, "atk": o.atk_bonus(), "ac": o.ac, "sv": o.saves.duplicate(), "spd": int(o.speed)}
	var keep_hp := o.hp
	o.level += 1
	o.recalc()
	var nxt := {"hp": o.max_hp, "atk": o.atk_bonus(), "sv": o.saves.duplicate()}
	o.level -= 1
	o.recalc()
	o.hp = keep_hp
	var rows := [
		["%s   level %d" % [o.display_name, o.level], "-> %d" % (o.level + 1)],
		["Hit points  %d" % now["hp"], "-> %d" % nxt["hp"]],
		["Attack  %+d" % now["atk"], "-> %+d" % nxt["atk"]],
		["Saves  F%+d R%+d W%+d" % [now["sv"]["fort"], now["sv"]["ref"], now["sv"]["will"]], "-> %+d %+d %+d" % [nxt["sv"]["fort"], nxt["sv"]["ref"], nxt["sv"]["will"]]],
	]
	var can := starlight >= cost
	for i in 4:
		var r := _sub(lp, lm["rows"][i])
		_text(Vector2(r.position.x + 7, r.get_center().y + 3), rows[i][0], 7, Color(0.95, 0.9, 0.78), true)
		var gw := ThemeDB.fallback_font.get_string_size(rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		_text(Vector2(r.end.x - gw - 6, r.get_center().y + 3), rows[i][1], 6, Color(0.6, 0.95, 0.6) if can else Color(0.6, 0.58, 0.54), true)
		var pl := _sub(lp, lm["plus"][i])
		if can and fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6:
			hud.draw_rect(pl.grow(-1), Color(1.0, 0.85, 0.4, 0.25))
	var ic: Array = lm["icons"]
	var vals := ["AC %d" % now["ac"], "Speed %d" % now["spd"], "Will %+d" % now["sv"]["will"]]
	for i in 3:
		var r2 := _sub(lp, ic[i])
		_text_c(r2.get_center().x, r2.end.y + 1, vals[i], 6, Color(0.9, 0.85, 0.72))
	# --- the shrine
	var cnt := _sub(rp, rm["count"])
	_text_c(cnt.get_center().x, cnt.get_center().y + 3, "%d" % starlight, 6, Color(0.88, 0.9, 1.0))
	var opts := _shrine_rows()
	for i in opts.size():
		var r3 := _sub(rp, rm["rows"][i])
		var on := i == shrine_i
		if on:
			hud.draw_rect(r3.grow(-1), Color(0.95, 0.7, 0.3, 0.22))
			hud.draw_rect(r3.grow(1), Color(1.0, 0.8, 0.4, 1.0), false, 1.0)
			_moth(Vector2(r3.end.x - 9, r3.get_center().y), Color(0.95, 0.8, 0.45))
		var col := Color(0.98, 0.92, 0.75) if opts[i][1] else Color(0.55, 0.52, 0.48)
		_text(Vector2(r3.position.x + 6, r3.get_center().y + 3), opts[i][0], 6, col, true)
	var fl: Array = o.feats.map(func(id): return Feats.info(id)["name"])
	var fr4 := _sub(rp, rm["rows"][4])
	var flines: Array = banter._wrap("Feats: " + (", ".join(fl) if not fl.is_empty() else "none yet"), fr4.size.x - 8, 6)
	for li in min(3, flines.size()):
		_text(Vector2(fr4.position.x + 4, fr4.position.y + 8 + li * 8), flines[li], 6, Color(0.62, 0.48, 0.72), false)
	var plate := _sub(rp, rm["plate"])
	_text_c(plate.get_center().x, plate.get_center().y + 3, "THE MOTH SHRINE", 7, Color(0.85, 0.85, 1.0))
	_text_c(W / 2, H - 4, "Up/Down + Enter   1 / Space: level up   F / Esc: leave   Your companions level up with you.", 6, Color(0.6, 0.6, 0.62))
	if not feat_offer.is_empty():
		_dim(0.55)
		_text_c(W / 2, 90, "%s reaches level %d. Choose a feat:" % [o.display_name, o.level], 9, Color(0.95, 0.88, 0.72))
		_draw_feat_cards(o)


func _draw_feat_cards(o: Hero) -> void:
	var W := 480.0
	var m: Vector2 = hud.get_local_mouse_position()
	for k in feat_offer.size():
		var fr := _feat_card(k)
		var f: Dictionary = Feats.info(feat_offer[k])
		var hot := fr.has_point(m)
		var own: bool = f["who"] == o.hero_id
		var ct: Texture2D = Art.ui("card")
		if ct != null:
			# DorkTeach's bone-sealed card: name above the bone, what it does below
			hud.draw_texture_rect(ct, fr, false, Color(1.1, 1.05, 0.95) if hot else Color(0.82, 0.8, 0.78))
			if hot:
				hud.draw_rect(fr.grow(1), Color(1.0, 0.82, 0.45), false, 1.0)
			elif own:
				hud.draw_rect(fr.grow(1), Color(0.75, 0.55, 0.9, 0.8), false, 1.0)
		else:
			hud.draw_rect(fr, Color(0.14, 0.11, 0.09, 0.95) if hot else Color(0.07, 0.06, 0.06, 0.95))
			hud.draw_rect(fr, Color(1.0, 0.82, 0.45) if hot else (Color(0.75, 0.55, 0.9) if own else Color(0.35, 0.3, 0.24)), false, 1.0)
		_text_c(fr.get_center().x, fr.position.y + 22, "[%d]" % (k + 1), 7, Color(0.65, 0.6, 0.54), false)
		var nl: Array = banter._wrap(f["name"], fr.size.x - 18, 8)
		for ni in nl.size():
			_text_c(fr.get_center().x, fr.position.y + 38 + ni * 9 - (nl.size() - 1) * 4, nl[ni], 8, Color(0.98, 0.9, 0.72), true)
		var dl: Array = banter._wrap(f["desc"], fr.size.x - 18, 6)
		for di in min(dl.size(), 5):
			_text_c(fr.get_center().x, fr.position.y + 76 + di * 8, dl[di], 6, Color(0.78, 0.75, 0.68), false)
		if own:
			_text_c(fr.get_center().x, fr.end.y - 9, o.display_name + " only", 6, Color(0.8, 0.62, 0.95), false)
	_text_c(W / 2, 236, "1 / 2 / 3 or click to choose", 7, Color(0.6, 0.6, 0.65))


## The older flat shrine screen (if the shrine art is missing).
func _draw_level_menu_plain(W: float, H: float) -> void:
	var r := Rect2(W / 2 - 150, 50, 300, 196 if not feat_offer.is_empty() else 160)
	_panel(r, 0.95)
	_text_c(W / 2, 66, "THE MOTH SHRINE", 12, Color(0.85, 0.85, 1.0))
	_text_c(W / 2, 78, "Starlight: %d" % starlight, 8, Color(0.75, 0.75, 0.9))
	var o: Hero = leader
	if not feat_offer.is_empty():
		_text_c(W / 2, 94, "%s reaches level %d. Choose a feat:" % [o.display_name, o.level], 8, Color(0.95, 0.88, 0.72))
		var m: Vector2 = hud.get_local_mouse_position()
		for k in feat_offer.size():
			var fr := _feat_card(k)
			var f: Dictionary = Feats.info(feat_offer[k])
			var hot := fr.has_point(m)
			var own: bool = f["who"] == o.hero_id
			var ct: Texture2D = Art.ui("card")
			if ct != null:
				# DorkTeach's bone-sealed card: name above the bone, what it does below
				hud.draw_texture_rect(ct, fr, false, Color(1.1, 1.05, 0.95) if hot else Color(0.82, 0.8, 0.78))
				if hot:
					hud.draw_rect(fr.grow(1), Color(1.0, 0.82, 0.45), false, 1.0)
				elif own:
					hud.draw_rect(fr.grow(1), Color(0.75, 0.55, 0.9, 0.8), false, 1.0)
			else:
				hud.draw_rect(fr, Color(0.14, 0.11, 0.09, 0.95) if hot else Color(0.07, 0.06, 0.06, 0.95))
				hud.draw_rect(fr, Color(1.0, 0.82, 0.45) if hot else (Color(0.75, 0.55, 0.9) if own else Color(0.35, 0.3, 0.24)), false, 1.0)
			_text_c(fr.get_center().x, fr.position.y + 22, "[%d]" % (k + 1), 7, Color(0.65, 0.6, 0.54), false)
			var nl: Array = banter._wrap(f["name"], fr.size.x - 18, 8)
			for ni in nl.size():
				_text_c(fr.get_center().x, fr.position.y + 38 + ni * 9 - (nl.size() - 1) * 4, nl[ni], 8, Color(0.98, 0.9, 0.72), true)
			var dl: Array = banter._wrap(f["desc"], fr.size.x - 18, 6)
			for di in min(dl.size(), 5):
				_text_c(fr.get_center().x, fr.position.y + 76 + di * 8, dl[di], 6, Color(0.78, 0.75, 0.68), false)
			if own:
				_text_c(fr.get_center().x, fr.end.y - 9, o.display_name + " only", 6, Color(0.8, 0.62, 0.95), false)
		_text_c(W / 2, 236, "1 / 2 / 3 or click to choose", 7, Color(0.6, 0.6, 0.65))
		return
	var cost := Hero.level_cost(o.level)
	_portrait_big(o.hero_id, Rect2(r.position.x + 12, 88, 42, 42), false)
	var col := Color(0.92, 0.86, 0.74) if starlight >= cost else Color(0.55, 0.52, 0.48)
	_text(Vector2(r.position.x + 60, 100), "%s   level %d  ->  %d" % [o.display_name, o.level, o.level + 1], 9, col)
	_text(Vector2(r.position.x + 60, 112), "Cost: %d Starlight     + a feat of your choice" % cost, 7, col)
	_text(Vector2(r.position.x + 60, 124), "HP %d  AC %d  attack %+d  Fort %+d  Ref %+d  Will %+d" % [o.max_hp, o.ac, o.atk_bonus(), o.saves["fort"], o.saves["ref"], o.saves["will"]], 6, Color(0.62, 0.6, 0.55))
	var fl: Array = o.feats.map(func(id): return Feats.info(id)["name"])
	_text(Vector2(r.position.x + 60, 134), "Feats: " + (", ".join(fl) if not fl.is_empty() else "none yet"), 6, Color(0.7, 0.62, 0.8))
	_text_c(W / 2, 156, "[1] / [Space] / click: level up", 8, Color(0.85, 0.82, 0.7))
	_text_c(W / 2, 170, "Your companions level up with you and choose their own feats.", 6, Color(0.6, 0.6, 0.62))
	_text_c(W / 2, 196, "[F] or [Esc] to leave", 7, Color(0.6, 0.6, 0.65))


func _draw_select(W: float, H: float) -> void:
	hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
	_text_c(W / 2, 30, "CHOOSE YOUR HERO", 16, Color(0.88, 0.8, 0.62))
	_text_c(W / 2, 42, "The others follow you and fight on their own.", 7, Color(0.65, 0.62, 0.58))
	var blurbs := {
		"average": ["Average", "Human barbarian", "Huge axe swings, Rage,", "Glory: LOOK AT ME!"],
		"puck": ["Puck", "Elf rogue / mesmerist", "Rapier, herb smoke, the Haze,", "and Nana's ghost on his side"],
		"brokk": ["Brokk", "Dwarf arcane archer", "Spell arrows, Many Shot,", "and a book of grudges"],
		"sael": ["Eowilas", "Elf cleric of the Black Butterfly", "Weak blade, strong prayers:", "heal, Silence, free, revive"],
	}
	var t := Time.get_ticks_msec() / 1000.0
	for i in 4:
		var id: String = HERO_IDS[i]
		var x := 20.0 + i * 110.0
		var sel := i == select_i
		_panel(Rect2(x, 54, 100, 176), 0.9 if sel else 0.7)
		if sel:
			hud.draw_rect(Rect2(x, 54, 100, 176), Color(0.85, 0.68, 0.32), false, 1.0)
		if Art.hd_has(id):
			var pm: Dictionary = Art.hd_pose(id, "idle")
			var ptex := Art.tex(pm["tex"])
			var pw: float = pm["w"]
			var ph: float = pm["h"]
			var k: float = min(90.0 / pw, 108.0 / ph)
			var breathe: float = 1.0 + (0.02 * sin(t * 2.4) if sel else 0.0)
			var dh := ph * k * breathe
			hud.draw_texture_rect(ptex, Rect2(x + 50 - pw * k / 2.0, 168 - dh, pw * k, dh), false, Color(1, 1, 1) if sel else Color(0.5, 0.5, 0.55))
			var bb: Array = blurbs[id]
			_text_c(x + 50, 178, "[%d] %s" % [i + 1, bb[0]], 9, Color(0.95, 0.88, 0.72) if sel else Color(0.7, 0.66, 0.6))
			_text_c(x + 50, 190, bb[1], 6, Color(0.7, 0.68, 0.62), false)
			_text_c(x + 50, 205, bb[2], 6, Color(0.6, 0.6, 0.6), false)
			_text_c(x + 50, 214, bb[3], 6, Color(0.6, 0.6, 0.6), false)
			continue
		var meta: Dictionary = Art.manifest["characters"][id]
		var fw: float = meta["frame_w"]
		var fh: float = meta["frame_h"]
		var a: Dictionary = meta["anims"]["walk_down" if sel else "idle_down"]
		var frame := int(t * (10.0 if sel else 4.0)) % int(a["count"])
		var src := Rect2((a["col"] + frame) * fw, a["row"] * fh, fw, fh)
		var scale: float = 0.92 * float(meta.get("scale", 0.5)) / 0.5
		hud.draw_texture_rect_region(Art.tex(id), Rect2(x + 50 - fw * scale / 2.0, 62, fw * scale, fh * scale), src, Color(1, 1, 1) if sel else Color(0.55, 0.55, 0.6))
		var b: Array = blurbs[id]
		_text_c(x + 50, 178, "[%d] %s" % [i + 1, b[0]], 9, Color(0.95, 0.88, 0.72) if sel else Color(0.7, 0.66, 0.6))
		_text_c(x + 50, 190, b[1], 6, Color(0.7, 0.68, 0.62), false)
		_text_c(x + 50, 205, b[2], 6, Color(0.6, 0.6, 0.6), false)
		_text_c(x + 50, 214, b[3], 6, Color(0.6, 0.6, 0.6), false)
	_text_c(W / 2, 250, "A / D or click to choose     Enter to begin", 8, Color(0.8, 0.78, 0.7))


func _slot_icon(hid: String, slot: String) -> String:
	match slot:
		"weapon": return {"average": "greataxe", "puck": "rapier", "brokk": "storm_quiver", "sael": "shuriken"}.get(hid, "rapier")
		"trinket": return "rune"
	return {"puck": "gigglecap", "brokk": "grudge_book", "sael": "dreamleaf"}.get(hid, "")


# =====================================================================
# Headless autotest: the party (all AI) walks the whole act
# =====================================================================

func autotest_goal() -> Variant:
	if ui != "play":
		return null
	if active_area != "":
		# hunt down whatever is still standing around in this area
		var best: Variant = null
		for e in area_enemies.get(active_area, []):
			if is_instance_valid(e) and not e.is_dead() and (best == null or e.global_position.distance_to(leader.global_position) < best.distance_to(leader.global_position)):
				best = e.global_position
		if best != null and best.distance_to(leader.global_position) > 50.0:
			return best
		return null
	var route: Array = L["route"]
	if route_i >= route.size():
		return null
	var wp := _v(route[route_i])
	if leader.global_position.distance_to(wp) < 22.0:
		route_i += 1
		return null
	# pushed off the road (a fight, a dodge): walk back to the last waypoint first
	if route_i > 0 and not _clear_line(leader.global_position, wp):
		var back := _v(route[route_i - 1])
		if leader.global_position.distance_to(back) > 12.0:
			return back
	return wp


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 10.0)
	for i in range(1, n):
		# the ground only: rocks and stalls are small, the steering walks round those
		var q := a.lerp(b, float(i) / n)
		if (walk_img != null and not _mask_ok(q)) or (walk_img == null and not is_walkable(q, 6.0)):
			return false
	return true


func _autotest(delta: float) -> void:
	if test_t == 0.0:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--goto-pos="):
				var c: PackedStringArray = arg.substr(11).split(",")
				for i in heroes.size():
					heroes[i].position = Vector2(float(c[0]) + i * 12, float(c[1]) + (i % 2) * 10)
				var bi := 0
				for k in L["route"].size():
					if _v(L["route"][k]).distance_to(heroes[0].position) < _v(L["route"][bi]).distance_to(heroes[0].position):
						bi = k
				route_i = bi
				camera.global_position = heroes[0].global_position
			if arg.begins_with("--goto="):
				# screenshot tests: start the party at the edge of an area
				for a in areas:
					if a["id"] == arg.substr(7):
						for i in heroes.size():
							heroes[i].position = a["pos"] + Vector2(-a["r"] * 0.6 + i * 10, a["r"] * 0.3)
						var best := 0
						for k in L["route"].size():
							if _v(L["route"][k]).distance_to(a["pos"]) < _v(L["route"][best]).distance_to(a["pos"]):
								best = k
						route_i = best
						camera.global_position = heroes[0].global_position
	test_t += delta
	if "--shot" in OS.get_cmdline_user_args():
		var at: float = float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shot") + 1]) if OS.get_cmdline_user_args().size() > OS.get_cmdline_user_args().find("--shot") + 1 else 7.0
		if test_t > at:
			get_viewport().get_texture().get_image().save_png("/tmp/shot.png")
			get_tree().quit()
			return
	if "--show-select" in OS.get_cmdline_user_args():
		ui = "select"
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cutscene=") and not banter.talk_active and test_t > float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shot") + 1]) - 1.5:
			banter.test_mode = true
			banter.talk(arg.substr(11), false)
			for k in int(OS.get_environment("CUT_SKIP") if OS.get_environment("CUT_SKIP") != "" else "0"):
				await get_tree().process_frame
				banter.type_t = 999.0
				var ev := InputEventKey.new()
				ev.physical_keycode = KEY_ENTER
				ev.pressed = true
				banter.talk_input(ev)
				await get_tree().create_timer(0.05, true).timeout
		if arg.begins_with("--show-ui=") and test_t > float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shot") + 1]) - 0.3:
			ui = arg.substr(10)
			if ui == "shrine":
				ui = "level"
				starlight = max(starlight, 400)
			elif ui == "level" and feat_offer.is_empty() and not leader.feats.is_empty():
				pass
			if ui.begins_with("shop_"):
				starlight = max(starlight, 2500)
				if leader.gear["weapon"].is_empty():
					leader.equip(Items.make("weapon", 0.3))
				camp.open_shop(ui.substr(5))
				ui = "shop"
			var want_sockets := ui == "sockets"
			if want_sockets:
				ui = "inventory"
				if bag.filter(func(b): return b["slot"] == "sigil").is_empty():
					for sg in ["fire", "moth", "thorn", "lightning"]:
						bag.append(Items.make_sigil(sg))
				if leader.gear["weapon"].is_empty():
					leader.equip(Items.make("weapon", 0.3))
			menu_back = "pause" if ui != "title" else "title"
			if ui == "level" and feat_offer.is_empty() and arg.ends_with("=level"):
				leader.add_feat("toughness")
				feat_offer = Feats.offer(leader.hero_id, leader.feats)
			if ui == "inventory" and bag.is_empty():
				seed(7)
				for i in 13:
					bag.append(Items.make(["weapon", "armor", "trinket"][i % 3], 0.15))
				leader.equip(Items.make("weapon", 0.0))
				leader.equip(Items.make("armor", 0.1))
				inv.open()
				inv.cur = 4
			if want_sockets and not inv.sock_open:
				inv.open()
				inv.cur = 0
				leader.gear["weapon"]["sockets"] = 3
				Items.socket(leader.gear["weapon"], "eye")
				inv.open_sockets()
			if arg.ends_with("dicelog"):
				ui = "play"
				Settings.dice_log = true
	if ui == "level" and not "--shot" in OS.get_cmdline_user_args():
		# exercise the level-up menu once
		if not test_flags.has("lvl"):
			test_flags["lvl"] = true
			starlight += 2000
			try_level_up(leader)
		ui = "play"
	if not test_flags.has("rest") and test_t > 1.0 and not "--shot" in OS.get_cmdline_user_args():
		test_flags["rest"] = true
		try_rest()
	if area_state.get(L.get("gate_after", "chapel" if Run.act == 1 else "grove")) == "cleared" and not gate_open and not test_flags.has("gate"):
		test_flags["gate"] = true
		open_gate()
	if int(test_t * 10) % 50 == 0 and active_area != "" and not "--shot" in OS.get_cmdline_user_args():
		var i := int(test_t / 5.0) % 4
		var hh: Hero = heroes[i]
		if not hh.is_dead():
			for n in [1, 2, 3]:
				hh.ability(n)
			hh.use_cast()
			hh.use_special()
			hh.drink()
	if int(test_t * 60) % 1800 == 0:
		print("  [t=%d] area=%s route=%d/%d leader=%s pos=%s starlight=%d state=%d tgt=%s mv=%s goal=%s ui=%s paused=%s ts=%s vel=%s conds=%s" % [test_t, active_area, route_i, L["route"].size(), leader.display_name, leader.global_position.round(), starlight, leader.state, leader.ai_target, leader.move_input, autotest_goal(), ui, get_tree().paused, Engine.time_scale, leader.velocity.round(), leader.conditions.keys()])
	if boss_dead and Run.act < Run.LAST_ACT and "--chain" in OS.get_cmdline_user_args() and banner_t < 3.0:
		print("AUTOTEST act %d done t=%.1f -> rift" % [Run.act, test_t])
		for h in heroes:
			print("  %s lvl %d" % [h.display_name, h.level])
		enter_rift()
		return
	if test_t > 600.0 or boss_dead and banner_t < 3.0:
		print("AUTOTEST end act %d" % Run.act)
		print("AUTOTEST end: t=%.1f boss_dead=%s kills=%d deaths=%d starlight=%d gate=%s" % [test_t, boss_dead, kills, deaths, starlight, gate_open])
		for h in heroes:
			print("  %s dodges=%d feats=%s" % [h.display_name, h.dash_count, h.feats])
			var bs: Array = h.bt_stats.keys()
			bs.sort_custom(func(a, b): return h.bt_stats[a] > h.bt_stats[b])
			print("    brain: " + ", ".join(bs.map(func(k): return "%s %d" % [k, h.bt_stats[k]])))
			print("  %s lvl %d hp %d/%d dead=%s gear=%s" % [h.display_name, h.level, h.hp, h.max_hp, h.is_dead(), ", ".join(["weapon", "armor", "trinket"].map(func(s): return Items.describe(h.gear[s], h.hero_id) if not h.gear[s].is_empty() else "-"))])
		get_tree().quit()
