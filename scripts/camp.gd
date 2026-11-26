extends Node
## The camp followers (DorkTeach's town-hub sheets). A blacksmith, an alchemist and a gambler
## pitch their stations beside the Moth Shrine in every act, next to the party's stash chest.
## Walk up and press F: each one has a small shop that runs on Starlight.

const NPCS := {
	"smith": {"name": "Harrow", "title": "the Blacksmith", "station": "station_forge", "npc": "npc_smith",
		"off": Vector2(170, -80), "light": Color(1.0, 0.55, 0.2), "energy": 1.0,
		"greet": ["Bring me steel and Starlight. I'll make it sing.", "Mind the anvil. It bites.", "Every edge dulls. Mine less."]},
	"alchemist": {"name": "Old Wick", "title": "the Alchemist", "station": "station_alchemy", "npc": "npc_alchemist",
		"off": Vector2(-185, -55), "light": Color(0.45, 1.0, 0.55), "energy": 0.7,
		"greet": ["Drink it fast. Don't smell it.", "Bog water, moth dust, a pinch of luck. Works every time.", "Ah. Still alive. Good for business."]},
	"gambler": {"name": "Grin", "title": "the Gambler", "station": "station_dice", "npc": "npc_gambler",
		"off": Vector2(180, 75), "light": Color(1.0, 0.75, 0.4), "energy": 0.8,
		"greet": ["Fortune favours the foolish. Feeling foolish?", "Roll the bones, friend.", "No refunds. Ever."]},
	"stash": {"name": "The Stash", "title": "", "station": "stash", "npc": "", "off": Vector2(-35, -125)},
}
const SLOTS := ["weapon", "armor", "trinket"]
const MAX_ENH := 5
const MAX_DRAUGHTS := 8

var main: Node
var spots: Dictionary = {}       # id -> where you talk to them
var bobs: Array = []             # [{node, base}]
var shop := ""
var sel := 0
var view := 0                    # whose gear the smith works on
var msg := ""
var msg_col := Color(0.8, 0.9, 0.7)
var greet := ""
var t := 0.0


func build() -> void:
	var camp: Dictionary = main.areas[0]
	for a in main.areas:
		if a["id"] == "camp":
			camp = a
	var c: Vector2 = camp["pos"]
	var avoid: Array = [main.shrine_pos, main.rift_pos]
	for p in main.L["props"]:
		if p["name"] == "campfire":
			avoid.append(main._v(p["pos"]))
	for id in NPCS:
		var d: Dictionary = NPCS[id]
		var off: Vector2 = d["off"]
		var p := c + off
		var k := 1.0
		# pull in toward the middle of the camp until there is room
		while k > 0.35 and (not main.is_walkable(p, 30.0) or avoid.any(func(q): return q.distance_to(p) < 60.0)):
			k -= 0.06
			p = c + off * k
		_station(d["station"], p, id == "stash")
		main.solids.append({"pos": p, "r": 16.0 if id != "smith" else 22.0})
		if d["npc"] != "":
			var np := p + (c - p).normalized() * 34.0 + Vector2(0, 6)
			var spr := _station(d["npc"], np, false)
			spr.flip_h = np.x > c.x + 30.0
			bobs.append({"node": spr, "base": spr.scale})
			spots[id] = np
			var l: PointLight2D = main._make_light(d["light"], d["energy"], 2.2, 30.0)
			l.position = p + Vector2(0, -24)
			main.world.add_child(l)
			main.flicker_lights.append(l)
		else:
			spots[id] = p


func _station(tex_name: String, p: Vector2, _small: bool) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = Art.prop(tex_name)
	if sp.texture != null:
		sp.scale = Vector2(0.25, 0.25)
		sp.offset = Vector2(0, -sp.texture.get_height() / 2.0 + 6.0)
	sp.position = p
	main.actors.add_child(sp)
	return sp


func _process(delta: float) -> void:
	t += delta
	for b in bobs:
		if is_instance_valid(b["node"]):
			b["node"].scale = Vector2(b["base"].x, b["base"].y * (1.0 + 0.012 * sin(t * 2.2 + b["base"].x * 50.0)))


func near(p: Vector2) -> String:
	for id in spots:
		if p.distance_to(spots[id]) < 34.0:
			return id
	return ""


func prompt(p: Vector2) -> String:
	var id := near(p)
	if id == "":
		return ""
	if id == "stash":
		return "F  open the stash (party & gear)"
	return "F  talk to %s %s" % [NPCS[id]["name"], NPCS[id]["title"]]


func try_interact(p: Vector2) -> bool:
	var id := near(p)
	if id == "":
		return false
	if id == "stash":
		Sfx.play("loot", null, -4.0, 0.0)
		main.set_ui("inventory")
		return true
	if not main.banter.seen.has("npc_" + id) and not main.autotest:
		main.banter.seen["npc_" + id] = true
		main.banter.talk("npc_" + id)
		return true
	open_shop(id)
	return true


func open_shop(id: String) -> void:
	shop = id
	sel = 0
	view = main.heroes.find(main.leader)
	msg = ""
	greet = NPCS[id]["greet"].pick_random()
	main.set_ui("shop")


# ---------------------------------------------------------------- offers

func hero() -> Hero:
	return main.heroes[clamp(view, 0, main.heroes.size() - 1)]


func _scale() -> float:
	return 1.0 + 0.3 * (Run.act - 1)


## [{label, cost, ok, note, act}] — act is called after the Starlight is paid.
func offers() -> Array:
	var out: Array = []
	match shop:
		"smith":
			var h := hero()
			for slot in SLOTS:
				var it: Dictionary = h.gear[slot]
				var nm: String = Items.describe(it, h.hero_id) if not it.is_empty() else "(no %s)" % slot
				var e: int = int(it.get("enh", 0))
				out.append({"label": "Temper %s" % nm, "cost": int(220 * pow(e + 1, 1.5) * _scale()),
					"ok": not it.is_empty() and e < MAX_ENH and it.get("slot", "") != "sigil",
					"note": ("+%d -> +%d %s" % [e, e + 1, "attack and damage" if slot == "weapon" else ("AC" if slot == "armor" else "to saves")]) if e < MAX_ENH else "As sharp as steel gets.",
					"act": func():
						it["enh"] = e + 1
						h.recalc()})
				var n := Items.sockets(it)
				out.append({"label": "Punch a socket: %s" % nm, "cost": int(350 * (n + 1) * _scale()),
					"ok": not it.is_empty() and n < Items.MAX_SOCKETS,
					"note": ("sockets %d -> %d (sigils go in with R in the party screen)" % [n, n + 1]) if n < Items.MAX_SOCKETS else "No room for another socket.",
					"act": func(): it["sockets"] = n + 1})
		"alchemist":
			out.append({"label": "Refill a draught  (%d/%d)" % [main.draughts, main.draught_max], "cost": 45,
				"ok": main.draughts < main.draught_max, "note": "One more swig before the shrine.", "act": func(): main.draughts += 1})
			out.append({"label": "A longer flask belt  (%d -> %d)" % [main.draught_max, main.draught_max + 1], "cost": int(650 * (main.draught_max - 4) * _scale()),
				"ok": main.draught_max < MAX_DRAUGHTS, "note": "Carry one more draught. For good.", "act": func():
					main.draught_max += 1
					main.draughts += 1})
			out.append({"label": "A strong brew for %s" % main.leader.display_name, "cost": int(120 * _scale()),
				"ok": main.leader.hp < main.leader.max_hp, "note": "Heals the leader fully, right now.", "act": func(): main.leader.heal(main.leader.max_hp)})
			out.append({"label": "A sigil stone (his pick)", "cost": int(420 * _scale()),
				"ok": main.bag.size() < main.BAG_SIZE, "note": "A random sigil, into the bag.", "act": func(): _give(Items.make_sigil())})
		"gambler":
			for slot in SLOTS:
				out.append({"label": "Gamble on %s" % {"weapon": "a weapon", "armor": "armour", "trinket": "a trinket"}[slot], "cost": int(300 * _scale()),
					"ok": main.bag.size() < main.BAG_SIZE, "note": "Sealed in a sack. Better odds than the bog.",
					"act": func(): _give(Items.make(slot, 0.35))})
			out.append({"label": "Gamble on a sigil", "cost": int(160 * _scale()), "ok": main.bag.size() < main.BAG_SIZE,
				"note": "Could be anything. Probably a rock.", "act": func(): _give(Items.make_sigil())})
			out.append({"label": "Double or nothing", "cost": 200, "ok": true, "note": "One coin. Heads you win 400.",
				"act": func(): _coin()})
	out.append({"label": "Leave", "cost": 0, "ok": true, "note": "", "act": func(): main.set_ui("play")})
	return out


func _give(it: Dictionary) -> void:
	main.bag.append(it)
	var col: Color = Items.SIGILS[it["sigil"]]["col"] if it["slot"] == "sigil" else Items.RARITY[it["rarity"]]
	msg = "Into the bag: " + Items.describe(it, main.leader.hero_id)
	msg_col = col
	main._on_log(msg)


func _coin() -> void:
	if randf() < 0.5:
		main.starlight += 400
		msg = "Heads. Grin pays up, scowling. (+400)"
		msg_col = Color(1.0, 0.9, 0.5)
		Sfx.play("starlight", null, -2.0, 0.0)
	else:
		msg = "Tails. \"Bad luck, friend.\""
		msg_col = Color(1.0, 0.5, 0.45)


func buy(i: int) -> void:
	var list := offers()
	if i < 0 or i >= list.size():
		return
	var o: Dictionary = list[i]
	if o["label"] == "Leave":
		o["act"].call()
		return
	if not o["ok"]:
		msg = "Not possible."
		msg_col = Color(0.8, 0.6, 0.5)
		Sfx.play("ui_back", null, -4.0, 0.0)
		return
	if main.starlight < o["cost"]:
		msg = "Not enough Starlight (%d needed)." % o["cost"]
		msg_col = Color(1.0, 0.5, 0.45)
		Sfx.play("ui_back", null, -4.0, 0.0)
		return
	main.starlight -= o["cost"]
	msg = o["label"] + ": done."
	msg_col = Color(0.7, 1.0, 0.7)
	o["act"].call()
	Sfx.play("loot", null, -3.0, 0.0)
	main.save_now()


# ---------------------------------------------------------------- input

func _row_rect(i: int, n: int) -> Rect2:
	var pr := _panel_rect()
	var fr: Array = Art.ui_info("menu_panel").get("inner", [0.13, 0.34, 0.92, 0.9])
	var inner := Rect2(pr.position + Vector2(fr[0], fr[1]) * pr.size, Vector2(fr[2] - fr[0], fr[3] - fr[1]) * pr.size)
	var step: float = min(19.0, (inner.size.y - 4.0) / max(1, n))
	return Rect2(inner.position.x + 4, inner.position.y + 2 + i * step, inner.size.x - 8, step - 2)


func _panel_rect() -> Rect2:
	var pw := 300.0
	return Rect2(166, 4, pw, pw * 659.0 / 800.0)


func handle(event: InputEvent) -> void:
	var n := offers().size()
	if event is InputEventMouseMotion:
		var m: Vector2 = main.hud.get_local_mouse_position()
		for i in n:
			if _row_rect(i, n).has_point(m):
				sel = i
		return
	if not (event.is_pressed() and not event.is_echo()):
		return
	var k: int = event.physical_keycode if event is InputEventKey else -1
	var jb: int = event.button_index if event is InputEventJoypadButton else -1
	if k in [KEY_UP, KEY_W] or jb == JOY_BUTTON_DPAD_UP:
		sel = (sel + n - 1) % n
		Sfx.play("ui_move", null, -8.0, 0.0)
	elif k in [KEY_DOWN, KEY_S] or jb == JOY_BUTTON_DPAD_DOWN:
		sel = (sel + 1) % n
		Sfx.play("ui_move", null, -8.0, 0.0)
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F] or jb == JOY_BUTTON_A:
		buy(sel)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m2: Vector2 = main.hud.get_local_mouse_position()
		for i in n:
			if _row_rect(i, n).has_point(m2):
				sel = i
				buy(i)
	elif shop == "smith" and (k in [KEY_E, KEY_TAB] or jb == JOY_BUTTON_RIGHT_SHOULDER):
		view = (view + 1) % 4
	elif shop == "smith" and (k == KEY_Q or jb == JOY_BUTTON_LEFT_SHOULDER):
		view = (view + 3) % 4
	elif k == KEY_ESCAPE or jb in [JOY_BUTTON_B, JOY_BUTTON_START] or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT):
		main.set_ui("play")
	else:
		return
	main.get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- draw

func draw(W: float, H: float) -> void:
	var hud: Control = main.hud
	hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
	var d: Dictionary = NPCS[shop]
	# the trader: framed portrait, name and a line
	var pt: Texture2D = Art.portrait_framed(shop)
	var pr := Rect2(18, 14, 132, 132)
	if pt != null:
		hud.draw_texture_rect(pt, pr, false)
	main._text_c(pr.get_center().x, pr.end.y + 13, d["name"], 11, Color(0.95, 0.85, 0.62))
	main._text_c(pr.get_center().x, pr.end.y + 24, d["title"], 7, Color(0.7, 0.66, 0.6))
	var y := pr.end.y + 40
	for line in main.banter._wrap("\"" + greet + "\"", 140.0, 7):
		main._text(Vector2(14, y), line, 7, Color(0.86, 0.82, 0.74), true)
		y += 9
	var list := offers()
	sel = clamp(sel, 0, list.size() - 1)
	var note: String = list[sel]["note"]
	if note != "":
		y += 5
		for line in main.banter._wrap(note, 140.0, 6):
			main._text(Vector2(14, y), line, 6, Color(0.7, 0.75, 0.85), true)
			y += 8
	if shop == "smith":
		main._text(Vector2(14, H - 32), "Working on: %s   (Q / E)" % hero().display_name, 7, Color(0.9, 0.8, 0.55), true)
	if msg != "":
		for line in main.banter._wrap(msg, 146.0, 7):
			main._text(Vector2(14, H - 20), line, 7, msg_col, true)
			break
	# the offers, on the candle panel
	var pnl := _panel_rect()
	var mp: Texture2D = Art.ui("menu_panel")
	if mp != null:
		hud.draw_texture_rect(mp, pnl, false)
	else:
		main._panel(pnl, 0.95)
	var bar: Texture2D = Art.ui("menu_bar")
	for i in list.size():
		var o: Dictionary = list[i]
		var r := _row_rect(i, list.size())
		var on := i == sel
		var afford: bool = o["ok"] and main.starlight >= o["cost"]
		if bar != null:
			hud.draw_texture_rect(bar, r, false, Color(1.08, 1.0, 0.92) if on else Color(0.55, 0.52, 0.5))
		if on:
			hud.draw_rect(r.grow(1), Color(0.95, 0.75, 0.38, 0.9), false, 1.0)
		var col := Color(0.98, 0.92, 0.75) if afford or o["label"] == "Leave" else Color(0.55, 0.52, 0.48)
		var label: String = o["label"]
		while ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > r.size.x - 62 and label.length() > 8:
			label = label.substr(0, label.length() - 2)
		if label != o["label"]:
			label += "."
		main._text(Vector2(r.position.x + 10, r.get_center().y + 3), label, 7, col, true)
		if o["cost"] > 0:
			main._text(Vector2(r.end.x - 52, r.get_center().y + 3), "%d" % o["cost"], 7, Color(0.8, 0.85, 1.0) if afford else Color(0.6, 0.45, 0.45), true)
	# Starlight, under the panel
	var mt: Texture2D = Art.ui("moth")
	if mt != null:
		hud.draw_texture_rect(mt, Rect2(pnl.position.x + 10, H - 16, 12, 12), false)
	main._text(Vector2(pnl.position.x + 26, H - 6), "Starlight  %d" % main.starlight, 8, Color(0.85, 0.9, 1.0), true)
	main._text(Vector2(pnl.end.x - 150, H - 6), "Enter buy    Esc leave", 6, Color(0.55, 0.53, 0.5), true)
