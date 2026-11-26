extends Node
## Sound for Hollowmoth (autoload "Sfx"): one-shot effects (positional or flat),
## crossfading music layers (explore / combat / boss) and ambience loops.
## All sounds are synthesised by tools/audiogen/make_audio.py.

const SFX_DIR := "res://assets/audio/sfx/"
const VARIANTS := {"swing": 3, "hit": 3, "step": 4}

var _cache: Dictionary = {}
var _last_play: Dictionary = {}       # name -> time, to stop stacking
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_now := ""
var _amb: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music_a = _player("Music")
	_music_b = _player("Music")
	apply_volumes()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(max(0.0001, Settings.music_volume * 0.8)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(max(0.0001, Settings.sfx_volume)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(max(0.0001, Settings.sfx_volume * 0.7)))


func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	elif FileAccess.file_exists(path):
		# not imported yet (new files): load straight from disk
		if path.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
		elif path.ends_with(".wav"):
			s = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	_cache[path] = s
	return s


## Play a sound effect. pos = world position for 3D-ish panning/falloff, or null for UI/flat.
func play(name: String, pos: Variant = null, volume_db := 0.0, pitch_var := 0.08) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(name, -1.0)) < 0.045:
		return
	_last_play[name] = now
	var file := name
	if VARIANTS.has(name):
		file = "%s_%d" % [name, randi() % VARIANTS[name]]
	var s := _stream(SFX_DIR + file + ".wav")
	if s == null:
		return
	var pitch := 1.0 + randf_range(-pitch_var, pitch_var)
	var scene := get_tree().current_scene
	if pos != null and scene != null:
		var p := AudioStreamPlayer2D.new()
		p.stream = s
		p.bus = "SFX"
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.max_distance = 420.0
		p.attenuation = 1.6
		p.position = pos
		scene.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "SFX"
		p.volume_db = volume_db
		p.pitch_scale = pitch
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


## Crossfade to a music layer: "explore", "combat", "boss" or "" for silence.
func music(layer: String, fade := 1.5) -> void:
	if layer == _music_now:
		return
	_music_now = layer
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_b, "volume_db", -60.0, fade)
	if layer != "":
		var s := _stream("res://assets/audio/music/%s.ogg" % layer)
		if s is AudioStreamOggVorbis:
			s.loop = true
		_music_a.stream = s
		_music_a.volume_db = -60.0
		_music_a.play()
		tw.tween_property(_music_a, "volume_db", 0.0, fade)


## Background ambience (rain and wind) for the outdoors.
func ambience(on: bool, rain := true) -> void:
	for p in _amb:
		p.queue_free()
	_amb.clear()
	if not on:
		return
	for n in ([["rain", -13.0], ["wind", -12.0]] if rain else [["wind", -8.0]]):
		var p := _player("Ambience")
		var s := _stream("res://assets/audio/amb/%s.ogg" % n[0])
		if s is AudioStreamOggVorbis:
			s.loop = true
		p.stream = s
		# ease in so the world doesn't start with a wall of noise
		p.volume_db = -50.0
		p.play()
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(p, "volume_db", n[1], 4.0).set_trans(Tween.TRANS_SINE)
		_amb.append(p)


## A looping positional fire crackle (campfire, braziers).
func fire_at(parent: Node, pos: Vector2, volume_db := -4.0) -> void:
	var s := _stream("res://assets/audio/amb/fire.ogg")
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		s.loop = true
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.max_distance = 160.0
	p.attenuation = 2.0
	p.position = pos
	parent.add_child(p)
	p.play(randf() * 6.0)
