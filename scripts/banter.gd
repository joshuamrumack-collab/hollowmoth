extends Node
## Party banter, driven by Dialogue Manager (res://dialogue/party.dialogue).
## say(cue): lines play as speech bubbles over the speakers while the game runs.
## talk(cue): a paused conversation box with portraits and choices (shrine scenes).

const PATH := "res://dialogue/party.dialogue"
const SPEAKERS := {"Average": "average", "Puck": "puck", "Brokk": "brokk", "Eowilas": "sael", "Nana": "puck"}
## Nana speaks only while Puck lives, but she has her own face.
const PORTRAITS := {"Nana": "nana", "Harrow": "smith", "Old Wick": "alchemist", "Grin": "gambler"}
## The camp followers speak in conversations only (they are not party members).
const NPC_SPEAKERS := ["Harrow", "Old Wick", "Grin"]
const COLORS := {"Average": Color(0.95, 0.72, 0.55), "Puck": Color(0.65, 0.8, 1.0), "Nana": Color(0.8, 0.9, 0.85),
	"Brokk": Color(0.95, 0.82, 0.45), "Eowilas": Color(0.85, 0.78, 1.0),
	"Harrow": Color(1.0, 0.62, 0.35), "Old Wick": Color(0.6, 0.95, 0.6), "Grin": Color(0.85, 0.65, 0.95)}

var main: Node
var res: Resource
var busy := false                 # a bubble sequence is playing
var bubbles: Array = []           # [{hero, name, text, t, life}]
var cooldown := 0.0
var idle_t := 0.0                 # time since the last fight or chat, for walking banter
var seen: Dictionary = {}         # one-off cues already played



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(PATH):
		res = load(PATH)
	elif FileAccess.file_exists(PATH):
		res = DialogueManager.create_resource_from_text(FileAccess.get_file_as_string(PATH))


func _hero(name: String) -> Hero:
	var id: String = SPEAKERS.get(name, "")
	for h in main.heroes:
		if h.hero_id == id:
			return h
	return null


func _can_speak(name: String) -> bool:
	var h := _hero(name)
	return h != null and not h.is_dead()


# ---------------------------------------------------------------- bubbles

## Play a cue as speech bubbles. Skips lines whose speaker is dead.
func say(cue: String, once := false, force := false) -> void:
	if res == null or (busy and not force) or (cooldown > 0.0 and not force):
		return
	if once:
		if seen.has(cue):
			return
		seen[cue] = true
	busy = true
	idle_t = 0.0
	var line = await DialogueManager.get_next_dialogue_line(res, cue)
	while line != null:
		if _can_speak(line.character) and line.text.strip_edges() != "":
			var life: float = clamp(1.4 + line.text.length() * 0.045, 1.8, 4.5)
			bubbles.append({"hero": _hero(line.character), "name": line.character, "text": line.text, "t": 0.0, "life": life})
			if line.character == "Nana":
				_hero("Nana").nana_act("cheer", life)
			await get_tree().create_timer(life * 0.85, false).timeout
		if line.next_id == "" or line.next_id == "end" or "END" in str(line.next_id):
			break
		line = await DialogueManager.get_next_dialogue_line(res, line.next_id)
	busy = false
	cooldown = 6.0


## A single random line from one hero's cue (e.g. "encounter_brokk").
func hero_line(prefix: String, hero_id: String, chance := 1.0) -> void:
	if randf() > chance:
		return
	say("%s_%s" % [prefix, hero_id])


## Someone in the party remarks on something (random living speaker).
func party_line(prefix: String, chance := 1.0) -> void:
	var alive: Array = main.heroes.filter(func(h): return not h.is_dead())
	if alive.is_empty() or randf() > chance:
		return
	hero_line(prefix, alive[randi() % alive.size()].hero_id)


var still_t := 0.0


## A one-off line in a hero's bubble (for lines built from game numbers).
func quip(h: Hero, text: String) -> void:
	if h == null or h.is_dead() or busy:
		return
	bubbles.append({"hero": h, "name": h.display_name, "text": text, "t": 0.0, "life": clamp(1.4 + text.length() * 0.045, 1.8, 4.5)})
	cooldown = 4.0


func _process(delta: float) -> void:
	if talk_active:
		_cut_process(delta)
		return
	if get_tree().paused:
		return
	cooldown = max(0.0, cooldown - delta)
	for b in bubbles:
		b["t"] += delta
	bubbles = bubbles.filter(func(b): return b["t"] < b["life"] and is_instance_valid(b["hero"]))
	# walking banter when nothing has happened for a while
	if main.ui == "play" and main.active_area == "" and not busy:
		idle_t += delta
		if idle_t > 55.0:
			idle_t = 0.0
			say(("banter_act%d" % Run.act) if Run.act >= 2 and randf() < 0.6 else "banter")
	# standing around: someone does their thing
	if main.ui == "play" and main.active_area == "" and main.leader != null and main.leader.velocity.length() < 5.0:
		still_t += delta
		if still_t > 8.0 and not busy:
			still_t = -6.0
			var who: Array = main.heroes.filter(func(h): return not h.is_dead())
			if not who.is_empty():
				var h: Hero = who.pick_random()
				h.emote({"average": "flex", "brokk": "scribble", "sael": "pray", "puck": "pipe"}[h.hero_id], 3.0)
				hero_line("idle", h.hero_id)
	else:
		still_t = 0.0


func draw_bubbles(hud: CanvasItem) -> void:
	var f := ThemeDB.fallback_font
	var xf: Transform2D = main.get_viewport().get_canvas_transform()
	for b in bubbles:
		var h: Hero = b["hero"]
		var a: float = clamp(b["t"] / 0.15, 0.0, 1.0) * clamp((b["life"] - b["t"]) / 0.3, 0.0, 1.0)
		var anchor: Vector2 = h.global_position + Vector2(0, -h.sprite_h - 16)
		if b["name"] == "Nana" and h.nana_sprite != null:
			anchor = h.nana_sprite.global_position + Vector2(0, -20)
		var p: Vector2 = xf * anchor
		var lines := _wrap(b["text"], 130.0, 7)
		var w := 0.0
		for l in lines:
			w = max(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x)
		var hgt := 10.0 + lines.size() * 8.0
		var r := Rect2(p.x - w / 2.0 - 5, p.y - hgt, w + 10, hgt)
		r.position.x = clamp(r.position.x, 2.0, 478.0 - r.size.x)
		r.position.y = clamp(r.position.y, 2.0, 200.0)
		hud.draw_rect(r, Color(0.05, 0.04, 0.05, 0.82 * a))
		hud.draw_rect(r, Color(0.45, 0.36, 0.26, 0.9 * a), false, 1.0)
		var tip := Vector2(clamp(p.x, r.position.x + 6, r.end.x - 6), r.end.y)
		hud.draw_colored_polygon(PackedVector2Array([tip + Vector2(-3, 0), tip + Vector2(3, 0), tip + Vector2(0, 4)]), Color(0.05, 0.04, 0.05, 0.82 * a))
		var col: Color = COLORS.get(b["name"], Color.WHITE)
		hud.draw_string(f, r.position + Vector2(5, 8), b["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(col.r, col.g, col.b, a))
		for i in lines.size():
			hud.draw_string(f, r.position + Vector2(5, 16 + i * 8), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.94, 0.9, 0.82, a))


func _wrap(text: String, width: float, size: int) -> Array:
	var f := ThemeDB.fallback_font
	var out: Array = []
	var cur := ""
	for word in text.split(" "):
		var test := word if cur == "" else cur + " " + word
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		out.append(cur)
	return out


# ---------------------------------------------------------------- cutscenes
# Letterboxed text box with the speaker's portrait popping up on the left or right.
# The previous speaker stays dimmed on the other side. Text types itself out;
# the first press finishes the line, the next press advances. Choices appear above the box.

var talk_line = null              # DialogueLine
var talk_choice := 0
var talk_active := false
var cut_t := 0.0                  # time since the cutscene opened (letterbox slide)
var type_t := 0.0                 # time since the current line started
var slots := {"left": "", "right": ""}   # who stands on each side
var pop := {"left": 1.0, "right": 1.0}   # 0 -> 1 pop-in animation per side
var active_side := "left"

const TYPE_SPEED := 45.0          # characters per second


var test_mode := false            # lets the screenshot test open a cutscene during autotest


signal talk_done(cue: String)
var cur_cue := ""


func talk(cue: String, once := true) -> void:
	if res == null or (main.autotest and not test_mode):
		talk_done.emit.call_deferred(cue)
		return
	if once:
		if seen.has(cue):
			return
		seen[cue] = true
	bubbles.clear()
	cur_cue = cue
	talk_active = true
	talk_choice = 0
	cut_t = 0.0
	slots = {"left": "", "right": ""}
	main.set_ui("talk")
	talk_line = await DialogueManager.get_next_dialogue_line(res, cue)
	await _skip_dead_lines()
	_on_new_line()


func _speaker_ok(name: String) -> bool:
	return name == "" or name == "Narrator" or name in NPC_SPEAKERS or _can_speak(name)


func _skip_dead_lines() -> void:
	while talk_line != null and talk_line.responses.is_empty() and not _speaker_ok(talk_line.character):
		talk_line = await DialogueManager.get_next_dialogue_line(res, talk_line.next_id)
	if talk_line == null:
		_end_talk()


func _on_new_line() -> void:
	if talk_line == null:
		return
	type_t = 0.0
	Sfx.play("talk_blip", null, -6.0, 0.05)
	var who: String = talk_line.character
	if who == "" or who == "Narrator":
		return
	if slots["left"] == who:
		active_side = "left"
	elif slots["right"] == who:
		active_side = "right"
	else:
		# a new face takes the side the current speaker isn't on
		var side := "right" if slots["left"] != "" and active_side == "left" else "left"
		if slots["left"] == "":
			side = "left"
		slots[side] = who
		pop[side] = 0.0
		active_side = side


func _end_talk() -> void:
	talk_active = false
	talk_line = null
	main.set_ui("play")
	cooldown = 10.0
	talk_done.emit(cur_cue)


func _typed_all() -> bool:
	return talk_line == null or type_t * TYPE_SPEED >= talk_line.text.length()


func talk_input(event: InputEvent) -> void:
	if talk_line == null:
		return
	var pressed: bool = (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	main.get_viewport().set_input_as_handled()
	main.menu_frame = Engine.get_process_frames()
	var key: int = event.physical_keycode if event is InputEventKey else -1
	var pad: int = event.button_index if event is InputEventJoypadButton else -1
	var n: int = talk_line.responses.size()
	if n > 0 and (key in [KEY_W, KEY_UP] or pad == JOY_BUTTON_DPAD_UP):
		talk_choice = (talk_choice + n - 1) % n
		return
	if n > 0 and (key in [KEY_S, KEY_DOWN] or pad == JOY_BUTTON_DPAD_DOWN):
		talk_choice = (talk_choice + 1) % n
		return
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F, KEY_E] or pad == JOY_BUTTON_A or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if not _typed_all():
			type_t = 999.0
			return
		var next_id: String = talk_line.responses[talk_choice].next_id if n > 0 else talk_line.next_id
		talk_choice = 0
		talk_line = await DialogueManager.get_next_dialogue_line(res, next_id)
		await _skip_dead_lines()
		_on_new_line()
	elif key == KEY_ESCAPE or pad == JOY_BUTTON_B:
		_end_talk()


func _cut_process(delta: float) -> void:
	cut_t += delta
	type_t += delta
	for side in pop:
		pop[side] = min(1.0, pop[side] + delta * 4.0)


func draw_talk(hud: CanvasItem) -> void:
	if talk_line == null:
		return
	var W := 480.0
	var H := 270.0
	var f := ThemeDB.fallback_font
	# letterbox
	var bar: float = 20.0 * clamp(cut_t / 0.35, 0.0, 1.0)
	hud.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35 * clamp(cut_t / 0.35, 0.0, 1.0)))
	hud.draw_rect(Rect2(0, 0, W, bar), Color(0, 0, 0))
	hud.draw_rect(Rect2(0, H - bar, W, bar), Color(0, 0, 0))
	var who: String = talk_line.character
	var narrator: bool = who == "" or who == "Narrator"
	var bt: Texture2D = Art.ui("dlg_box")
	if bt == null:
		_draw_talk_plain(hud, W, H, bar, who, narrator)
	else:
		# DorkTeach's dialogue frame: the speaker in the portrait well, text to the right
		var meta: Dictionary = Art.ui_info("dlg_box")
		var bw := W - 16.0
		var bh := bw * float(bt.get_height()) / float(bt.get_width())
		var box := Rect2(8, H - bar - bh - 2.0 + lerp(18.0, 0.0, clamp(cut_t / 0.3, 0.0, 1.0)), bw, bh)
		var sub := func(key: String) -> Rect2:
			var fr: Array = meta.get(key, [0.02, 0.2, 0.17, 0.9])
			return Rect2(box.position + Vector2(fr[0], fr[1]) * box.size, Vector2(fr[2] - fr[0], fr[3] - fr[1]) * box.size)
		var well: Rect2 = sub.call("well")
		var text: Rect2 = sub.call("text")
		hud.draw_texture_rect(bt, box, false)
		if not narrator and (SPEAKERS.has(who) or PORTRAITS.has(who)):
			var p: float = pop.get(active_side, 1.0)
			var pt := Art.portrait(PORTRAITS.get(who, SPEAKERS.get(who, "")))
			if pt != null:
				var g: float = lerp(-6.0, 0.0, clamp(p, 0.0, 1.0))
				hud.draw_texture_rect(pt, well.grow(g), false, Color(1, 1, 1, clamp(p * 1.5, 0.0, 1.0)))
		else:
			# the narrator: a moth flickering in the empty well
			var mt: Texture2D = Art.ui("dlg_moth")
			if mt != null:
				var q: float = well.size.x * 0.6
				hud.draw_texture_rect(mt, Rect2(well.get_center() - Vector2(q, q) / 2.0 + Vector2(0, sin(cut_t * 2.0) * 1.5), Vector2(q, q)), false, Color(1, 1, 1, 0.55))
		var col_name: Color = COLORS.get(who, Color(0.8, 0.78, 0.72))
		var ty := text.position.y + 10.0
		if not narrator:
			hud.draw_string(f, Vector2(text.position.x + 4, ty), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col_name)
			ty += 12.0
		var shown: String = talk_line.text.substr(0, int(type_t * TYPE_SPEED))
		var lines := _wrap(shown, text.size.x - 30.0, 8)
		var tcol := Color(0.8, 0.78, 0.72) if narrator else Color(0.95, 0.91, 0.84)
		for i in lines.size():
			hud.draw_string(f, Vector2(text.position.x + 4, ty + i * 10.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tcol)
		var n: int = talk_line.responses.size()
		if n > 0 and _typed_all():
			var bar_t: Texture2D = Art.ui("menu_bar")
			for i in n:
				var sel := i == talk_choice
				var txt: String = talk_line.responses[i].text
				var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
				var r := Rect2(W / 2 - max(tw / 2 + 18, 70), box.position.y - 6.0 - (n - i) * 17.0, max(tw + 36, 140), 15)
				if bar_t != null:
					hud.draw_texture_rect(bar_t, r, false, Color(1, 1, 1) if sel else Color(0.6, 0.58, 0.56))
				else:
					hud.draw_rect(r, Color(0.06, 0.04, 0.04, 0.92))
				if sel:
					hud.draw_rect(r.grow(1), Color(0.95, 0.75, 0.4), false, 1.0)
				hud.draw_string(f, Vector2(W / 2 - tw / 2, r.position.y + 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.93, 0.75) if sel else Color(0.78, 0.74, 0.66))
		elif _typed_all():
			# the moth glyph from the sheet: "go on"
			var mt2: Texture2D = Art.ui("dlg_moth")
			var a: float = 0.55 + 0.45 * sin(cut_t * 4.0)
			if mt2 != null:
				hud.draw_texture_rect(mt2, Rect2(text.end - Vector2(16, 15), Vector2(13, 13)), false, Color(1, 1, 1, a))
	hud.draw_string(f, Vector2(W - 92, H - 6), "F / Enter    Esc skip", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.5, 0.48, 0.45))


## The old flat box (used if the dialogue art is missing).
func _draw_talk_plain(hud: CanvasItem, W: float, H: float, bar: float, who: String, narrator: bool) -> void:
	var f := ThemeDB.fallback_font
	# portraits: the active one large and lit, the other dimmed
	for side in ["left", "right"]:
		var name: String = slots[side]
		if name == "" or not SPEAKERS.has(name):
			continue
		var active: bool = side == active_side and not narrator
		var p: float = pop[side]
		var e: float = 1.0 + 0.12 * sin(p * PI) if p < 1.0 else 1.0     # overshoot
		var size: float = (84.0 if active else 66.0) * lerp(0.6, 1.0, p) * e
		var base_x: float = 22.0 if side == "left" else W - 22.0 - size
		var y: float = H - bar - 74.0 - size + lerp(30.0, 0.0, p)
		var col := Color(1, 1, 1, p) if active else Color(0.45, 0.42, 0.45, p)
		var pt := Art.portrait_framed(PORTRAITS.get(name, SPEAKERS[name]))
		if pt != null:
			hud.draw_texture_rect(pt, Rect2(base_x, y, size, size), false, col)
	# text box
	var box := Rect2(58, H - bar - 72, W - 116, 66)
	hud.draw_rect(box, Color(0.035, 0.028, 0.03, 0.94))
	hud.draw_rect(box.grow(-2), Color(0.3, 0.24, 0.17, 0.9), false, 1.0)
	hud.draw_rect(box, Color(0.62, 0.48, 0.3), false, 1.0)
	for c in [box.position, Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), box.end]:
		hud.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(0.75, 0.6, 0.35))
	var col_name: Color = COLORS.get(who, Color(0.8, 0.78, 0.72))
	if not narrator:
		var nw := f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var nx := box.position.x + 14.0 if active_side == "left" else box.end.x - nw - 14.0
		hud.draw_rect(Rect2(nx - 6, box.position.y - 9, nw + 12, 14), Color(0.07, 0.05, 0.05, 0.95))
		hud.draw_rect(Rect2(nx - 6, box.position.y - 9, nw + 12, 14), Color(0.6, 0.45, 0.25), false, 1.0)
		hud.draw_string(f, Vector2(nx, box.position.y + 2), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col_name)
	var shown: String = talk_line.text.substr(0, int(type_t * TYPE_SPEED))
	var lines := _wrap(shown, box.size.x - 32.0, 8)
	var tcol := Color(0.78, 0.76, 0.7) if narrator else Color(0.95, 0.91, 0.84)
	for i in lines.size():
		hud.draw_string(f, box.position + Vector2(16, 22 + i * 11), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tcol)
	var n: int = talk_line.responses.size()
	if n > 0 and _typed_all():
		for i in n:
			var sel := i == talk_choice
			var y := box.position.y - 16.0 - (n - 1 - i) * 14.0 - 4.0
			var txt: String = talk_line.responses[i].text
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var r := Rect2(W / 2 - tw / 2 - 12, y - 10, tw + 24, 13)
			hud.draw_rect(r, Color(0.06, 0.04, 0.04, 0.92))
			hud.draw_rect(r, Color(0.8, 0.6, 0.3) if sel else Color(0.35, 0.28, 0.2), false, 1.0)
			hud.draw_string(f, Vector2(W / 2 - tw / 2, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.98, 0.9, 0.7) if sel else Color(0.7, 0.66, 0.6))
	elif _typed_all() and fmod(cut_t, 1.0) < 0.6:
		hud.draw_string(f, box.end - Vector2(22, 8), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.75, 0.45))

