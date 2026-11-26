extends SceneTree
func _initialize() -> void:
	var sfx = root.get_node("Sfx")
	var bad := 0
	for f in DirAccess.get_files_at("res://assets/audio/sfx"):
		if f.ends_with(".wav"):
			if sfx._stream("res://assets/audio/sfx/" + f) == null: bad += 1; print("missing ", f)
	for f in ["music/explore.ogg", "music/combat.ogg", "music/boss.ogg", "amb/rain.ogg", "amb/wind.ogg", "amb/fire.ogg"]:
		var s = sfx._stream("res://assets/audio/" + f)
		if s == null: bad += 1; print("missing ", f)
		else: print(f, " ", snapped(s.get_length(), 0.1), "s")
	print("AUDIO bad=", bad, " buses=", AudioServer.bus_count)
	quit()
