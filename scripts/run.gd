extends Node
## Autoload "Run": what survives between acts (the scene reloads for each act),
## and the save file (user://save.json), written at the shrine, on boss kills and between acts.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

const LAST_ACT := 3
const ACT_NAMES := ["", "The Hollowmarch Outskirts", "The Cinderveil", "The Starfall Mere"]
var act := 1
var carry: Dictionary = {}      # {heroes: {id: {level, gear, feats}}, leader, starlight, tactics, seen, bag}
var world: Dictionary = {}      # loaded save: {bosses_dead, cleared, gate_open, draughts, moth}
var resume := false             # the next scene load continues a save at the shrine
var level_override := ""        # "Try: <name>" on the title: play assets/level_<name>.json (never saved)


func reset() -> void:
	level_override = ""
	act = 1
	carry = {}
	world = {}
	resume = false


func snapshot(main: Node) -> Dictionary:
	var hs := {}
	for h in main.heroes:
		hs[h.hero_id] = {"level": h.level, "gear": h.gear.duplicate(true), "feats": h.feats.duplicate()}
	return {
		"heroes": hs, "leader": main.leader.hero_id, "starlight": main.starlight,
		"tactics": [main.tactics_rage, main.tactics_herbs, main.tactics_heal, main.tactics_draughts],
		"seen": main.banter.seen.duplicate(),
		"bag": main.bag.duplicate(true),
	}


## Snapshot the party and reload the scene as the next act.
func goto_act(n: int, main: Node) -> void:
	carry = snapshot(main)
	world = {}
	act = n
	resume = false
	save_game(main, true)
	Art.load_level(n)
	main.get_tree().paused = false
	main.get_tree().reload_current_scene()


## Apply a carried party to freshly built heroes. Returns the leader id ("" if none).
func apply(main: Node) -> String:
	if carry.is_empty():
		return ""
	for h in main.heroes:
		var c: Dictionary = carry["heroes"].get(h.hero_id, {})
		if c.is_empty():
			continue
		h.gear = c["gear"].duplicate(true)
		h.feats = c.get("feats", []).duplicate()
		while h.level < int(c["level"]):
			h.level += 1
		h.recalc()
		h.hp = h.max_hp
	main.starlight = int(carry["starlight"])
	var t: Array = carry["tactics"]
	main.tactics_rage = t[0]; main.tactics_herbs = t[1]; main.tactics_heal = t[2]; main.tactics_draughts = t[3]
	main.banter.seen = carry["seen"].duplicate()
	main.bag = carry.get("bag", []).duplicate(true)
	return carry["leader"]


# ---------------------------------------------------------------- save file

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## fresh_act: the save starts a new act (nothing cleared yet).
func save_game(main: Node, fresh_act := false) -> void:
	if main.autotest or level_override != "" or main.test_level:
		return
	var w := {}
	if not fresh_act:
		w = {
			"bosses_dead": main.bosses_dead.keys(), "cleared": main.areas_ever_cleared.keys(),
			"gate_open": main.gate_open, "draughts": main.draughts,
			"moth": {} if main.moth_drop.is_empty() else {"pos": [main.moth_drop["pos"].x, main.moth_drop["pos"].y], "amount": main.moth_drop["amount"]},
		}
	var data := {"version": SAVE_VERSION, "act": act, "party": carry if fresh_act else snapshot(main), "world": w,
		"time": Time.get_datetime_string_from_system()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write the save file")
		return
	f.store_string(JSON.stringify(data))


## Read the save into carry/world and mark the next scene load as a resume.
func load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or not d.has("party"):
		return false
	act = int(d["act"])
	carry = _fix_numbers(d["party"])
	world = d.get("world", {})
	resume = true
	Art.load_level(act)
	return true


func save_info() -> String:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return ""
	var p: Dictionary = d.get("party", {})
	var lid: String = p.get("leader", "")
	var lvl: int = int(p.get("heroes", {}).get(lid, {}).get("level", 1))
	var names := {"average": "Average", "puck": "Puck", "brokk": "Brokk", "sael": "Eowilas"}
	return "Act %d  -  %s, level %d" % [int(d.get("act", 1)), names.get(lid, lid), lvl]


## JSON turns every number into a float: items need ints back.
func _fix_numbers(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _fix_numbers(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _fix_numbers(x))
	if v is float and v == floor(v):
		return int(v)
	return v
