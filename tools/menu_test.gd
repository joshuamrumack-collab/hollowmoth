extends SceneTree
# Headless check of the menu flow: title -> select -> play -> pause -> options -> back -> resume.

var main: Node
var step := 0
var fails := 0

func key(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = p
		Input.parse_input_event(e)

func check(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	step += 1
	match step:
		10: check(main.ui == "title", "starts on title"); key(KEY_DOWN)
		14: check(main.menu_i == 1, "down moves to Options"); key(KEY_ENTER)
		18: check(main.ui == "options" and not paused, "options from title, not paused"); key(KEY_DOWN); key(KEY_ENTER)
		24: check(not root.get_node("Settings").screen_shake, "toggle screen shake off"); key(KEY_ENTER); key(KEY_ESCAPE)
		30: check(main.ui == "title" and main.menu_i == 1, "Esc returns to title on Options"); key(KEY_UP)
		34: key(KEY_ENTER)
		38: check(main.ui == "select", "Begin -> select"); key(KEY_ENTER)
		42: check(main.ui == "talk" and main.leader != null, "hero chosen -> opening cutscene"); key(KEY_ESCAPE)
		45: check(main.ui == "play", "Esc skips the cutscene"); key(KEY_ESCAPE)
		50: check(main.ui == "pause" and paused, "Esc pauses"); key(KEY_ESCAPE)
		56: check(main.ui == "play" and not paused, "Esc resumes (no reopen)"); key(KEY_ESCAPE)
		62: key(KEY_DOWN); key(KEY_DOWN)
		66: key(KEY_ENTER)
		70: check(main.ui == "options" and paused, "options from pause keeps game paused"); key(KEY_ESCAPE)
		76: check(main.ui == "pause" and main.menu_i == 2, "back to pause on Options"); key(KEY_UP); key(KEY_UP)
		80: key(KEY_ENTER)
		84: check(main.ui == "play" and not paused, "Resume"); key(KEY_I)
		90: check(main.ui == "inventory" and paused, "I opens party screen, paused"); key(KEY_ESCAPE)
		96: check(main.ui == "play" and not paused, "Esc closes party screen"); main.starlight = 1234; main.save_now()
		98:
			var run: Node = root.get_node("Run")
			check(run.has_save(), "save written")
			check(run.load_game() and run.carry["starlight"] == 1234 and run.carry["leader"] == main.leader.hero_id, "save loads back")
			check(run.save_info().begins_with("Act 1"), "save info: " + run.save_info())
			run.reset()
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
		100:
			root.get_node("Settings").screen_shake = true
			root.get_node("Settings").save()
			print("MENU TEST fails=%d" % fails)
			return true
	return false
