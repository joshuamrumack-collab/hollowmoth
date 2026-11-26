extends SceneTree
# The camp followers: walk up to each, buy something, check it happened.
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
		main.set_leader(main.heroes[0])
		main.set_ui("play")
	if step == 6:
		check(main.camp.spots.size() == 4, "four camp spots: %s" % [main.camp.spots.keys()])
		for id in ["smith", "alchemist", "gambler"]:
			check(main.is_walkable(main.camp.spots[id], 6.0), "%s stands on walkable ground" % id)
		main.starlight = 20000
		main.banter.seen["npc_smith"] = true
		main.banter.seen["npc_alchemist"] = true
		main.banter.seen["npc_gambler"] = true
		var h = main.leader
		h.equip(main.get_node("/root/Items").make("weapon", 0.0))
		# the smith
		main.leader.global_position = main.camp.spots["smith"]
		main.interact()
		check(main.ui == "shop" and main.camp.shop == "smith", "F at the smith opens his shop (ui=%s)" % main.ui)
		var e0: int = int(h.gear["weapon"]["enh"])
		var s0: int = main.starlight
		main.camp.view = main.heroes.find(h)
		main.camp.buy(0)
		check(int(h.gear["weapon"]["enh"]) == e0 + 1 and main.starlight < s0, "tempering adds +1 and costs Starlight")
		var n0: int = main.get_node("/root/Items").sockets(h.gear["weapon"])
		main.camp.buy(1)
		check(main.get_node("/root/Items").sockets(h.gear["weapon"]) == n0 + 1, "punching a socket adds one")
		main.camp.buy(main.camp.offers().size() - 1)
		check(main.ui == "play", "Leave closes the shop")
		# the alchemist
		main.leader.global_position = main.camp.spots["alchemist"]
		main.interact()
		var m0: int = main.draught_max
		main.camp.buy(1)
		check(main.draught_max == m0 + 1, "the flask belt adds a draught slot")
		var b0: int = main.bag.size()
		main.camp.buy(3)
		check(main.bag.size() == b0 + 1 and main.bag[-1]["slot"] == "sigil", "buying a sigil puts one in the bag")
		main.set_ui("play")
		# the gambler
		main.leader.global_position = main.camp.spots["gambler"]
		main.interact()
		b0 = main.bag.size()
		main.camp.buy(0)
		check(main.bag.size() == b0 + 1 and main.bag[-1]["slot"] == "weapon", "gambling gives a weapon")
		main.starlight = 10
		var s1: int = main.starlight
		main.camp.buy(0)
		check(main.starlight == s1 and main.bag.size() == b0 + 1, "can't gamble without the Starlight")
		main.set_ui("play")
		# the stash
		main.leader.global_position = main.camp.spots["stash"]
		main.interact()
		check(main.ui == "inventory", "the stash opens the party screen")
		main.set_ui("play")
		# the draught belt survives an act change
		var snap: Dictionary = main.get_node("/root/Run").snapshot(main)
		check(int(snap.get("draught_max", 0)) == main.draught_max, "flask belt is saved")
		print("CAMP TEST fails=%d" % fails)
		return true
	return false
