extends Node
## Player options, saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var fullscreen := true
var screen_shake := true
var hit_stop := true
var hit_flash := true
var dice_log := false
var hints := true
var music_volume := 0.75
var sfx_volume := 0.9


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		screen_shake = cfg.get_value("feel", "screen_shake", screen_shake)
		hit_stop = cfg.get_value("feel", "hit_stop", hit_stop)
		hit_flash = cfg.get_value("feel", "hit_flash", hit_flash)
		dice_log = cfg.get_value("hud", "dice_log", dice_log)
		hints = cfg.get_value("hud", "hints", hints)
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	apply_video()


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("feel", "screen_shake", screen_shake)
	cfg.set_value("feel", "hit_stop", hit_stop)
	cfg.set_value("feel", "hit_flash", hit_flash)
	cfg.set_value("hud", "dice_log", dice_log)
	cfg.set_value("hud", "hints", hints)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(PATH)
