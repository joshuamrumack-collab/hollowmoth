extends Node
## The party screen (I): hero tabs, worn gear, the shared bag and a compare tooltip.
## Loot goes into the bag; you choose what each hero wears. Companions also find
## and equip their own gear as you go (see main.companion_finds()).

const COLS := 8
const ROWS := 3
const CELL := 25.0
const SLOTS := ["weapon", "armor", "trinket"]

var main: Node
var view := 0           # which hero's tab is open (index into main.heroes)
var cur := 3            # 0..2 = worn slots, 3.. = bag cells
var flash_t := 0.0      # brief highlight after an action
var msg := ""

# layout (480x270 HUD): paper doll left, bag right, tooltip below
var panel := Rect2(14, 12, 452, 246)            # (kept for the menu test)
var doll := Rect2(8, 8, 196, 190)
var bagp := Rect2(208, 8, 264, 190)
var bag_pos := Vector2(230, 44)
var tip := Rect2(8, 200, 464, 58)
const WORN_AT := [Vector2(22, 128), Vector2(22, 80), Vector2(144, 80)]   # weapon, armor, trinket (relative to doll)

# sigil socketing (R)
var sock_open := false
var sock_target := 0     # index into _sock_targets()
var sock_pick := 0       # index into _bag_sigils()
var sock_from_bag: Dictionary = {}


func open() -> void:
	view = main.heroes.find(main.leader)
	cur = 3 if not main.bag.is_empty() else 0
	msg = ""


func hero() -> Hero:
	return main.heroes[view]


func item_at(i: int) -> Dictionary:
	if i < 3:
		return hero().gear[SLOTS[i]]
	var b := i - 3
	return main.bag[b] if b < main.bag.size() else {}


func _cell_rect(i: int) -> Rect2:
	if i < 3:
		return Rect2(doll.position + WORN_AT[i], Vector2(30, 30))
	var b := i - 3
	return Rect2(bag_pos + Vector2((b % COLS) * (CELL + 2), int(b / COLS) * (CELL + 2)), Vector2(CELL, CELL))


# ---------------------------------------------------------------- input

func handle(event: InputEvent) -> void:
	if sock_open:
		_sock_handle(event)
		return
	if event is InputEventMouseMotion:
		var m: Vector2 = main.hud.get_local_mouse_position()
		for i in 3 + COLS * ROWS:
			if _cell_rect(i).has_point(m):
				cur = i
		return
	var pressed: bool = event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	if event is InputEventMouseButton:
		var m2: Vector2 = main.hud.get_local_mouse_position()
		for t in 4:
			if _tab_rect(t).has_point(m2):
				view = t
				return
		if event.button_index == MOUSE_BUTTON_LEFT:
			use()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			salvage()
		return
	var k: int = event.physical_keycode if event is InputEventKey else -1
	var jb: int = event.button_index if event is InputEventJoypadButton else -1
	if k in [KEY_LEFT, KEY_A] or jb == JOY_BUTTON_DPAD_LEFT:
		_move(-1, 0)
	elif k in [KEY_RIGHT, KEY_D] or jb == JOY_BUTTON_DPAD_RIGHT:
		_move(1, 0)
	elif k in [KEY_UP, KEY_W] or jb == JOY_BUTTON_DPAD_UP:
		_move(0, -1)
	elif k in [KEY_DOWN, KEY_S] or jb == JOY_BUTTON_DPAD_DOWN:
		_move(0, 1)
	elif k in [KEY_ENTER, KEY_SPACE, KEY_F, KEY_KP_ENTER] or jb == JOY_BUTTON_A:
		use()
	elif k in [KEY_X, KEY_DELETE, KEY_BACKSPACE] or jb == JOY_BUTTON_X:
		salvage()
	elif k == KEY_R or jb == JOY_BUTTON_Y:
		open_sockets()
	elif k in [KEY_TAB, KEY_E] or jb == JOY_BUTTON_RIGHT_SHOULDER:
		view = (view + 1) % 4
	elif k == KEY_Q or jb == JOY_BUTTON_LEFT_SHOULDER:
		view = (view + 3) % 4
	elif k in [KEY_1, KEY_2, KEY_3, KEY_4]:
		view = k - KEY_1
	else:
		return
	main.get_viewport().set_input_as_handled()


func _move(dx: int, dy: int) -> void:
	Sfx.play("ui_move", null, -8.0, 0.0)
	if cur < 3:
		if dx > 0 and cur == 2:
			cur = 3
		else:
			cur = clamp(cur + dx, 0, 2)
		return
	var b := cur - 3
	var c := b % COLS
	var r := int(b / COLS)
	if dx < 0 and c == 0:
		cur = 2
		return
	c = clamp(c + dx, 0, COLS - 1)
	r = clamp(r + dy, 0, ROWS - 1)
	cur = 3 + r * COLS + c


## Equip the selected bag item on the viewed hero, or take off the selected worn item.
func use() -> void:
	var h := hero()
	if cur >= 3 and item_at(cur).get("slot", "") == "sigil":
		open_sockets()
		return
	if cur < 3:
		var slot: String = SLOTS[cur]
		if h.gear[slot].is_empty():
			return
		if main.bag.size() >= COLS * ROWS:
			msg = "The bag is full."
			return
		main.bag.append(h.gear[slot])
		h.gear[slot] = {}
		h.recalc()
		Sfx.play("ui_back", null, -4.0, 0.0)
		msg = "%s takes it off." % h.display_name
		return
	var it := item_at(cur)
	if it.is_empty():
		return
	main.bag.erase(it)
	var old: Dictionary = h.equip(it)
	if not old.is_empty():
		main.bag.insert(min(cur - 3, main.bag.size()), old)
	Sfx.play("loot", null, -4.0, 0.0)
	flash_t = 0.4
	msg = "%s equips %s." % [h.display_name, Items.describe(it, h.hero_id)]
	main._on_log(msg)


func salvage() -> void:
	if cur < 3:
		return
	var it := item_at(cur)
	if it.is_empty():
		return
	var v: int = value(it)
	main.bag.erase(it)
	main.starlight += v
	Sfx.play("starlight", null, -4.0, 0.0)
	msg = "Salvaged for %d Starlight." % v


static func value(it: Dictionary) -> int:
	return int(25 + Items.score(it) * 35)


# ---------------------------------------------------------------- compare

## Stats the hero would have wearing `it` (gear and HP are restored afterwards).
func preview(h: Hero, it: Dictionary) -> Dictionary:
	var keep_gear: Dictionary = h.gear.duplicate(true)
	var keep_hp: int = h.hp
	if not it.is_empty():
		h.gear[it["slot"]] = it
	h.recalc()
	var s := stats(h)
	h.gear = keep_gear
	h.recalc()
	h.hp = keep_hp
	return s


func stats(h: Hero) -> Dictionary:
	return {"HP": h.max_hp, "AC": h.ac, "Attack": h.atk_bonus(), "Damage": h.enh("weapon") + (1 if h.prop("bear") else 0), "Fort": h.saves["fort"], "Ref": h.saves["ref"],
		"Will": h.saves["will"], "Stamina": int(h.max_stamina), "Poise": int(h.poise_max), "Speed": int(h.speed)}


# ---------------------------------------------------------------- sigils

## Gear you can socket into: the viewed hero's worn items, plus a bag item if you opened it there.
func _sock_targets() -> Array:
	var h := hero()
	var out: Array = []
	if not sock_from_bag.is_empty():
		out.append(sock_from_bag)
	for slot in SLOTS:
		if not h.gear[slot].is_empty():
			out.append(h.gear[slot])
	return out


func _bag_sigils() -> Array:
	return main.bag.filter(func(it): return it.get("slot", "") == "sigil")


func open_sockets() -> void:
	var it := item_at(cur)
	sock_from_bag = it if (cur >= 3 and not it.is_empty() and it["slot"] != "sigil") else {}
	sock_target = 0
	if cur < 3 and not it.is_empty():
		sock_target = _sock_targets().find(it)
	sock_pick = 0
	if not it.is_empty() and it["slot"] == "sigil":
		sock_pick = max(0, _bag_sigils().find(it))
	if _sock_targets().is_empty():
		msg = "%s wears nothing to socket." % hero().display_name
		return
	sock_open = true
	Sfx.play("ui_confirm", null, -4.0, 0.0)


func _sock_handle(event: InputEvent) -> void:
	var pressed: bool = event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	var k: int = event.physical_keycode if event is InputEventKey else -1
	var jb: int = event.button_index if event is InputEventJoypadButton else -1
	var targets := _sock_targets()
	var sig := _bag_sigils()
	if k in [KEY_LEFT, KEY_A] or jb == JOY_BUTTON_DPAD_LEFT:
		sock_target = (sock_target + targets.size() - 1) % max(1, targets.size())
	elif k in [KEY_RIGHT, KEY_D] or jb == JOY_BUTTON_DPAD_RIGHT:
		sock_target = (sock_target + 1) % max(1, targets.size())
	elif k in [KEY_UP, KEY_W] or jb == JOY_BUTTON_DPAD_UP:
		sock_pick = (sock_pick + sig.size() - 1) % max(1, sig.size())
	elif k in [KEY_DOWN, KEY_S] or jb == JOY_BUTTON_DPAD_DOWN:
		sock_pick = (sock_pick + 1) % max(1, sig.size())
	elif k in [KEY_ENTER, KEY_SPACE, KEY_F, KEY_KP_ENTER] or jb == JOY_BUTTON_A or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		_do_socket()
	elif k in [KEY_ESCAPE, KEY_R, KEY_I] or jb in [JOY_BUTTON_B, JOY_BUTTON_Y] or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT):
		sock_open = false
		Sfx.play("ui_back", null, -4.0, 0.0)
	else:
		return
	Sfx.play("ui_move", null, -8.0, 0.0)
	main.get_viewport().set_input_as_handled()


func _do_socket() -> void:
	var targets := _sock_targets()
	var sig := _bag_sigils()
	if targets.is_empty() or sig.is_empty():
		msg = "No sigils in the bag. Enemies drop them now and then."
		return
	var it: Dictionary = targets[clamp(sock_target, 0, targets.size() - 1)]
	var sg: Dictionary = sig[clamp(sock_pick, 0, sig.size() - 1)]
	if not Items.socket(it, sg["sigil"]):
		msg = "No free socket left."
		Sfx.play("ui_back", null, -4.0, 0.0)
		return
	main.bag.erase(sg)
	hero().recalc()
	sock_pick = clamp(sock_pick, 0, max(0, _bag_sigils().size() - 1))
	flash_t = 0.5
	msg = "%s set into %s." % [Items.SIGILS[sg["sigil"]]["name"], Items.describe(it, hero().hero_id)]
	main._on_log(msg)
	Sfx.play("starlight", null, -2.0, 0.0)


# ---------------------------------------------------------------- draw

func _tab_rect(t: int) -> Rect2:
	return Rect2(doll.position.x + 14 + t * 43, doll.position.y + 12, 41, 16)


## A framed panel from DorkTeach's inventory sheet, drawn as a nine-patch so it fits any size.
func _frame(name: String, r: Rect2) -> void:
	var t: Texture2D = Art.ui(name)
	if t == null:
		main._panel(r, 0.97)
		return
	var sb := StyleBoxTexture.new()
	sb.texture = t
	var m := t.get_width() * 0.09
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	main.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.25, 0.25))
	main.hud.draw_style_box(sb, Rect2(r.position * 4.0, r.size * 4.0))
	main.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw(W: float, H: float) -> void:
	var hud: Control = main.hud
	flash_t = max(0.0, flash_t - get_process_delta_time())
	hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
	_frame("inv_panel", doll)
	_frame("inv_bag", bagp)
	# hero tabs
	for t in 4:
		var o: Hero = main.heroes[t]
		var tr := _tab_rect(t)
		var on := t == view
		hud.draw_rect(tr, Color(0.22, 0.17, 0.12, 0.95) if on else Color(0.06, 0.05, 0.05, 0.85))
		hud.draw_rect(tr, Color(0.75, 0.6, 0.35) if on else Color(0.3, 0.26, 0.2), false, 1.0)
		main._portrait(o.hero_id, Rect2(tr.position + Vector2(1, 1), Vector2(14, 14)), o.is_dead())
		main._text(tr.position + Vector2(17, 11), o.display_name.substr(0, 5), 6, Color(0.95, 0.88, 0.72) if on else Color(0.6, 0.57, 0.52))
		if o == main.leader:
			main._text(tr.position + Vector2(tr.size.x - 5, 6), "*", 6, Color(1.0, 0.85, 0.4))
	# the hero, standing in the middle of the doll
	var h := hero()
	main._text_c(doll.get_center().x, doll.position.y + 42, "%s   level %d" % [h.display_name, h.level], 8, Color(0.95, 0.88, 0.72))
	if Art.hd_has(h.hero_id):
		var pm: Dictionary = Art.hd_pose(h.hero_id, "idle")
		var pw: float = pm["w"]
		var ph: float = pm["h"]
		var k: float = min(80.0 / pw, 112.0 / ph)
		var feet := Vector2(doll.get_center().x, doll.position.y + 170)
		hud.draw_texture_rect(Art.tex(pm["tex"]), Rect2(feet.x - pw * k / 2.0, feet.y - ph * k, pw * k, ph * k), false, Color(1, 1, 1) if not h.is_dead() else Color(0.4, 0.4, 0.45))
	for i in 3:
		_draw_cell(i, h)
		var r := _cell_rect(i)
		main._text_c(r.get_center().x, r.end.y + 8, SLOTS[i].capitalize(), 6, Color(0.62, 0.58, 0.52), false)
	# the bag
	main._text(Vector2(bag_pos.x, bag_pos.y - 8), "BAG  %d/%d" % [main.bag.size(), COLS * ROWS], 7, Color(0.75, 0.62, 0.45), true)
	main._text(Vector2(bagp.end.x - 92, bag_pos.y - 8), "Starlight %d" % main.starlight, 7, Color(0.8, 0.85, 1.0), true)
	for i in range(3, 3 + COLS * ROWS):
		_draw_cell(i, h)
	# stats under the bag
	var s := stats(h)
	var sx := bag_pos.x
	var sy := bag_pos.y + ROWS * (CELL + 2) + 14
	main._text(Vector2(sx, sy), "HP %d/%d   AC %d   Attack %+d   Damage %+d" % [h.hp, h.max_hp, h.ac, s["Attack"], s["Damage"]], 7, Color(0.82, 0.78, 0.7), true)
	main._text(Vector2(sx, sy + 11), "Fort %+d   Ref %+d   Will %+d   Stamina %d   Poise %d" % [s["Fort"], s["Ref"], s["Will"], s["Stamina"], s["Poise"]], 6, Color(0.7, 0.67, 0.6), true)
	var fl: Array = h.feats.map(func(id): return main.Feats.info(id)["name"])
	var flines: Array = main.banter._wrap("Feats: " + (", ".join(fl) if not fl.is_empty() else "none yet"), bagp.size.x - 44, 6)
	for li in min(3, flines.size()):
		main._text(Vector2(sx, sy + 22 + li * 8), flines[li], 6, Color(0.72, 0.62, 0.82), true)
	var sc := _bag_sigils().size()
	if sc > 0:
		main._text(Vector2(sx, sy + 48), "%d sigil%s in the bag: press R to socket" % [sc, "s" if sc > 1 else ""], 6, Color(0.75, 0.85, 1.0), true)
	_draw_tooltip(h)
	var keys := "Arrows/mouse select   Enter wear   R sigils   X salvage   Q/E hero   I/Esc close"
	main._text_c(W / 2, H - 3, keys, 6, Color(0.55, 0.52, 0.48), false)
	if sock_open:
		_draw_sockets(W, H)


func _draw_cell(i: int, h: Hero) -> void:
	var hud: Control = main.hud
	var r := _cell_rect(i)
	var it := item_at(i)
	var bgt: Texture2D = Art.ui("inv_slot" if i < 3 else "inv_cell")
	if bgt != null:
		hud.draw_texture_rect(bgt, r.grow(2 if i < 3 else 0), false)
	else:
		hud.draw_rect(r, Color(0.03, 0.03, 0.035, 0.95))
	if not it.is_empty():
		var col: Color = Items.RARITY[it["rarity"]] if it["slot"] != "sigil" else Items.SIGILS[it["sigil"]]["col"]
		_draw_icon(it, h, r.grow(-4 if i < 3 else -2), col)
		if it["rarity"] != "normal" or it["slot"] == "sigil":
			hud.draw_rect(r.grow(-1), Color(col.r, col.g, col.b, 0.85), false, 1.0)
		# sockets as little pips along the bottom
		var n := Items.sockets(it)
		var have: Array = Items.sigils_of(it)
		for si in n:
			var p := Vector2(r.position.x + 4 + si * 5, r.end.y - 4)
			hud.draw_circle(p, 1.8, Color(0.05, 0.05, 0.06))
			if si < have.size():
				hud.draw_circle(p, 1.3, Items.SIGILS[have[si]]["col"])
			else:
				hud.draw_arc(p, 1.8, 0, TAU, 8, Color(0.55, 0.5, 0.42), 0.6)
		if i >= 3 and _better(h, it):
			# a small arrow: an upgrade for the hero you're looking at
			var q := r.position + Vector2(r.size.x - 7, 3)
			hud.draw_colored_polygon(PackedVector2Array([q + Vector2(2.5, 0), q + Vector2(5, 4), q + Vector2(0, 4)]), Color(0.4, 0.95, 0.45))
	elif i < 3:
		_draw_icon({"slot": SLOTS[i]}, h, r.grow(-6), Color(0.3, 0.29, 0.27))
	if i == cur and not sock_open:
		var c := Color(1.0, 0.9, 0.55) if flash_t <= 0.0 else Color(0.6, 1.0, 0.6)
		hud.draw_rect(r.grow(1), c, false, 1.0)


func _better(h: Hero, it: Dictionary) -> bool:
	if not h.gear.has(it.get("slot", "")):
		return false
	return Items.score(it) > Items.score(h.gear[it["slot"]])


## The painted icon for an item (DorkTeach's inventory sheet), per hero and slot.
func icon_for(it: Dictionary, hid: String) -> Texture2D:
	if it.get("slot", "") == "sigil":
		return Art.tex("sigil_" + str(it["sigil"]))
	var name := ""
	match it.get("slot", ""):
		"weapon":
			name = {"average": "axe", "puck": "sword", "brokk": "quiver", "sael": "shuriken"}.get(hid, "sword")
			if it.get("unique_id", "") == "grandmothers_thorn":
				name = "rapier"
			elif it.get("unique_id", "") == "iron_knuckle":
				name = "mace"
		"armor":
			name = {"average": "leather", "puck": "cuirass", "brokk": "plate", "sael": "cloak"}.get(hid, "leather")
		"trinket":
			var base := Items.trinket_base(it) if it.has("rarity") else "Amulet"
			name = {"Ring": "ring", "Amulet": "amulet", "Charm": "rune"}.get(base, "amulet")
	var t: Texture2D = Art.tex("icon_item_" + name) if name != "" else null
	return t if t != null else Art.icon(main._slot_icon(hid, it.get("slot", "")))


func _draw_icon(it: Dictionary, h: Hero, r: Rect2, col: Color) -> void:
	var hud: Control = main.hud
	var ic := icon_for(it, h.hero_id)
	if ic == null:
		return
	var tint := Color(1, 1, 1) if it.has("rarity") else col
	hud.draw_texture_rect(ic, r, false, tint)


func _draw_tooltip(h: Hero) -> void:
	var hud: Control = main.hud
	main._panel(tip, 0.95)
	hud.draw_rect(tip.grow(-3), Color(0.04, 0.035, 0.035, 0.75))
	var it := item_at(cur)
	var x := tip.position.x + 8
	var y := tip.position.y + 12
	if it.is_empty():
		var hint := msg if msg != "" else ("Empty slot." if cur < 3 else "Pick up loot to fill the bag. Items with a green arrow are upgrades for %s." % h.display_name)
		main._text(Vector2(x, y), hint, 7, Color(0.6, 0.58, 0.54))
		return
	if it["slot"] == "sigil":
		var sd: Dictionary = Items.SIGILS[it["sigil"]]
		main._text(Vector2(x, y), sd["name"], 8, sd["col"], true)
		main._text(Vector2(x, y + 11), "Socketed into gear: " + sd["text"] + ". Permanent.", 7, Color(0.75, 0.72, 0.66))
		main._text(Vector2(x, y + 24), "Enter / R: choose an item to socket it into      X / right-click: salvage for %d Starlight" % value(it), 6, Color(0.55, 0.53, 0.5))
		if msg != "":
			main._text(Vector2(x, y + 36), msg, 6, Color(0.8, 0.9, 0.7))
		return
	var col: Color = Items.RARITY[it["rarity"]]
	var socks := "   sockets %d/%d" % [Items.sigils_of(it).size(), Items.sockets(it)] if Items.sockets(it) > 0 else ""
	main._text(Vector2(x, y), "%s   (%s %s)%s" % [Items.describe(it, h.hero_id), it["rarity"], it["slot"], socks], 8, col, true)
	var det := Items.details(it)
	main._text(Vector2(x, y + 11), det if det != "" else "plain, no magic", 7, Color(0.75, 0.72, 0.66))
	if cur < 3:
		main._text(Vector2(x, y + 24), "Worn by %s.  Enter / click: take it off.   R: socket sigils." % h.display_name, 7, Color(0.6, 0.58, 0.54))
	else:
		# compare against what the hero wears now
		var worn: Dictionary = h.gear[it["slot"]]
		var now := stats(h)
		var then := preview(h, it)
		var parts := []
		for key in now:
			var d: int = int(then[key]) - int(now[key])
			if d != 0:
				parts.append({"t": "%s %+d" % [key, d], "good": d > 0})
		var vs := "vs " + (Items.describe(worn, h.hero_id) if not worn.is_empty() else "nothing") + ":"
		main._text(Vector2(x, y + 24), vs, 7, Color(0.6, 0.58, 0.54))
		var cx := x + 6.0 + ThemeDB.fallback_font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		if parts.is_empty():
			main._text(Vector2(cx, y + 24), "same stats", 7, Color(0.6, 0.58, 0.54))
		for p in parts:
			main._text(Vector2(cx, y + 24), p["t"], 7, Color(0.45, 0.95, 0.5) if p["good"] else Color(1.0, 0.45, 0.4))
			cx += ThemeDB.fallback_font.get_string_size(p["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 8
		main._text(Vector2(x, y + 37), "Enter / click: %s wears it    R: socket    X / right-click: salvage for %d Starlight" % [h.display_name, value(it)], 6, Color(0.55, 0.53, 0.5))
	if msg != "":
		main._text(Vector2(tip.end.x - 8 - ThemeDB.fallback_font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x, tip.position.y + 10), msg, 6, Color(0.8, 0.9, 0.7))


## The socketing altar (DorkTeach's sigil sheet): the item in the window, its sockets below,
## your sigils listed to the right.
func _draw_sockets(W: float, H: float) -> void:
	var hud: Control = main.hud
	hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
	var targets := _sock_targets()
	var sig := _bag_sigils()
	var h := hero()
	var it: Dictionary = targets[clamp(sock_target, 0, targets.size() - 1)]
	var meta: Dictionary = Art.ui_info("sigil_panel")
	var tex: Texture2D = Art.ui("sigil_panel")
	var ph := 236.0
	var pw := ph * 754.0 / 920.0
	var pr := Rect2(36, (H - ph) / 2.0, pw, ph)
	if tex != null:
		hud.draw_texture_rect(tex, pr, false)
	else:
		main._panel(pr, 0.97)
	var sub := func(key: String) -> Rect2:
		var f: Array = meta.get(key, [0.28, 0.24, 0.72, 0.62])
		return Rect2(pr.position + Vector2(f[0], f[1]) * pr.size, Vector2(f[2] - f[0], f[3] - f[1]) * pr.size)
	var win: Rect2 = sub.call("window")
	var ic := icon_for(it, h.hero_id)
	if ic != null:
		var q: float = min(win.size.x, win.size.y) * 0.8
		hud.draw_texture_rect(ic, Rect2(win.get_center() - Vector2(q, q) / 2.0, Vector2(q, q)), false)
	# arrows to switch item
	if targets.size() > 1:
		main._text_c(win.position.x - 7, win.get_center().y + 4, "<", 10, Color(0.95, 0.8, 0.45))
		main._text_c(win.end.x + 7, win.get_center().y + 4, ">", 10, Color(0.95, 0.8, 0.45))
	var n := Items.sockets(it)
	var have: Array = Items.sigils_of(it)
	var sl: Array = meta.get("sockets", [])
	for si in sl.size():
		var f: Array = sl[si]
		var sr := Rect2(pr.position + Vector2(f[0], f[1]) * pr.size, Vector2(f[2] - f[0], f[3] - f[1]) * pr.size)
		if si >= n:
			hud.draw_circle(sr.get_center(), sr.size.x * 0.42, Color(0.02, 0.02, 0.02, 0.85))
			continue
		if si < have.size():
			var st: Texture2D = Art.tex("sigil_" + str(have[si]))
			if st != null:
				hud.draw_texture_rect(st, sr.grow(1), false)
		elif fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.7:
			hud.draw_arc(sr.get_center(), sr.size.x * 0.45, 0, TAU, 16, Color(0.95, 0.85, 0.5, 0.8), 1.0)
	var plate: Rect2 = sub.call("plate")
	main._text_c(plate.get_center().x, plate.get_center().y + 3, Items.describe(it, h.hero_id), 6, Items.RARITY[it["rarity"]], true)
	# the list of sigils
	main._panel(Rect2(pr.end.x + 6, pr.position.y + 6, W - pr.end.x - 14, pr.size.y - 12), 0.96)
	var lx := pr.end.x + 14
	main._text(Vector2(lx, pr.position.y + 22), "SOCKET A SIGIL", 10, Color(0.88, 0.8, 0.62), true)
	main._text(Vector2(lx, pr.position.y + 34), "%s  -  sockets %d/%d" % [h.display_name, have.size(), n], 7, Color(0.7, 0.68, 0.62), true)
	if sig.is_empty():
		main._text(Vector2(lx, pr.position.y + 56), "No sigils in the bag.", 7, Color(0.6, 0.58, 0.54), true)
		main._text(Vector2(lx, pr.position.y + 67), "Enemies drop sigil stones now and then;", 6, Color(0.55, 0.53, 0.5), true)
		main._text(Vector2(lx, pr.position.y + 76), "bosses nearly always do.", 6, Color(0.55, 0.53, 0.5), true)
	var first: int = clamp(sock_pick - 5, 0, max(0, sig.size() - 9))
	for li in range(first, min(sig.size(), first + 9)):
		var sd: Dictionary = Items.SIGILS[sig[li]["sigil"]]
		var y := pr.position.y + 48 + (li - first) * 19
		var on := li == sock_pick
		if on:
			hud.draw_rect(Rect2(lx - 4, y - 2, 232, 18), Color(0.3, 0.2, 0.1, 0.6))
			hud.draw_rect(Rect2(lx - 4, y - 2, 232, 18), Color(0.85, 0.65, 0.3), false, 1.0)
		var st: Texture2D = Art.tex("sigil_" + str(sig[li]["sigil"]))
		if st != null:
			hud.draw_texture_rect(st, Rect2(lx, y - 1, 16, 16), false)
		main._text(Vector2(lx + 20, y + 6), sd["name"], 7, sd["col"] if on else sd["col"].darkened(0.3), true)
		main._text(Vector2(lx + 20, y + 14), sd["text"], 6, Color(0.75, 0.72, 0.66) if on else Color(0.55, 0.53, 0.5), true)
	var full := have.size() >= n
	var hint := "No free socket on this item." if full else "Enter: set the sigil (permanent)"
	main._text(Vector2(lx, pr.end.y - 26), hint, 7, Color(1.0, 0.55, 0.45) if full else Color(0.85, 0.82, 0.7), true)
	main._text(Vector2(lx, pr.end.y - 14), "Left/Right item   Up/Down sigil   Esc back", 6, Color(0.55, 0.53, 0.5), true)
	if msg != "" and flash_t > 0.0:
		main._text(Vector2(lx, pr.end.y - 38), msg, 6, Color(0.7, 1.0, 0.7), true)


func _prop_text(k: String) -> String:
	for pool in [Items.WEAPON_PREFIX, Items.WEAPON_SUFFIX, Items.ARMOR_SUFFIX, Items.TRINKET_SUFFIX]:
		if pool.has(k):
			return pool[k][1]
	return k
