extends SceneTree
# Continue from a save: write one, load it, build the scene, check the world came back.

var main: Node
var step := 0
var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1

func _initialize() -> void:
	var save := {"version": 1, "act": int(OS.get_environment("ACT") if OS.get_environment("ACT") != "" else "1"), "party": {
		"heroes": {"average": {"level": 4, "gear": {"weapon": {"slot": "weapon", "rarity": "rare", "enh": 2, "props": {"keen": true}, "name": ""}, "armor": {}, "trinket": {}}, "feats": []},
			"puck": {"level": 4, "gear": {"weapon": {}, "armor": {}, "trinket": {}}, "feats": []},
			"brokk": {"level": 3, "gear": {"weapon": {}, "armor": {}, "trinket": {}}, "feats": []},
			"sael": {"level": 4, "gear": {"weapon": {}, "armor": {}, "trinket": {}}, "feats": []}},
		"leader": "puck", "starlight": 777, "tactics": [true, true, 45, true], "seen": {"intro": true},
		"bag": [{"slot": "armor", "rarity": "magic", "enh": 1, "props": {}, "name": ""}]},
		"world": {"bosses_dead": ["pit"] if OS.get_environment("ACT") in ["", "1"] else ["mirror"], "cleared": ["glade"], "gate_open": true, "draughts": 3, "moth": {"pos": [600, 640], "amount": 120}}}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f.close()
	var run: Node = root.get_node("Run")
	check(run.load_game(), "load_game")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	step += 1
	if step == 10:
		check(main.ui == "play", "resumes straight into play (ui=%s)" % main.ui)
		check(main.leader.hero_id == "puck", "leader restored")
		check(main.hero("average").level == 4 and main.hero("average").gear["weapon"].get("enh") == 2, "levels and gear restored")
		check(main.starlight == 777 and main.bag.size() == 1 and main.draughts == 3, "starlight, bag, draughts")
		check(main.gate_open and not main.moth_drop.is_empty(), "gate open, starlight moth waiting")
		check(main.bosses_dead.size() == 1, "boss stays dead")
		print("RESUME TEST fails=%d" % fails)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
		return true
	return false
