extends SceneTree
# Title -> "Try: example" -> hero select -> play on the hand-drawn level, without saving.
var main: Node
var step := 0
var fails := 0

func check(c: bool, m: String) -> void:
	print(("ok   " if c else "FAIL ") + m)
	if not c:
		fails += 1

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	step += 1
	if step == 3:
		main = current_scene
	if step == 5:
		var items: Array = main._menu_list()
		check(items.has("Try: example"), "title lists the test level: %s" % [items])
		main.menu_i = items.find("Try: example")
		main._menu_confirm()
	if step == 30:
		main = current_scene if current_scene != null else root.get_child(root.get_child_count() - 1)
		check(main.test_level and main.walk_img != null, "scene reloaded on the test level with its walk mask")
		check(main.ui == "select", "goes to hero select (ui=%s)" % main.ui)
		main.started = true
		main.save_now()
		check(not FileAccess.file_exists("user://save.json"), "test levels never save")
		print("TRY TEST fails=%d" % fails)
		return true
	return false
