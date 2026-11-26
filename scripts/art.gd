extends Node
## Autoload "Art": loads the pixel-art sheets and the level layout made by artgen/.
## Character sheets become SpriteFrames with directional animations
## (idle/walk/attack/hurt/cast + _down/_side/_up, and dead).

var manifest: Dictionary = {}
var level: Dictionary = {}
var _frames := {}
var _tex := {}


func _ready() -> void:
	manifest = _load_json("res://assets/manifest.json")
	load_level(1)


## Act 1 is level.json, later acts level_<n>.json (written by artgen/level2.py).
func load_level(act: int) -> void:
	level = _load_json("res://assets/level.json" if act <= 1 else "res://assets/level_%d.json" % act)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing " + path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load_png("res://assets/%s.png" % name)
	return _tex[name]


## Loads a PNG through the importer, or straight from disk if Godot hasn't imported it yet
## (new art dropped into the folder while the editor was closed or still scanning).
func load_png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func prop(name: String) -> Texture2D:
	return tex("prop_" + name)


## A CanvasTexture (colour + normal map, optional specular) so 2D lights shade it.
func lit(name: String, specular: String = "", shininess: float = 0.5, spec_color: Color = Color(1, 1, 1)) -> Texture2D:
	var key := "lit:" + name
	if _tex.has(key):
		return _tex[key]
	var ct := CanvasTexture.new()
	ct.diffuse_texture = tex(name)
	var nt := load_png("res://assets/%s_n.png" % name)
	if nt != null:
		ct.normal_texture = nt
	if specular != "":
		var st := load_png("res://assets/%s.png" % specular)
		if st != null:
			ct.specular_texture = st
		ct.specular_shininess = shininess
		ct.specular_color = spec_color
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex[key] = ct
	return ct


func prop_lit(name: String) -> Texture2D:
	if manifest["props"].get(name, {}).get("normal", false):
		return lit("prop_" + name)
	return prop(name)


func prop_scale(name: String) -> float:
	return float(manifest["props"].get(name, {}).get("scale", 0.5))


func char_meta(id: String) -> Dictionary:
	return manifest["characters"][id]


func anim_fps(anim_name: String) -> float:
	if anim_name.begins_with("walk"):
		return 13.0
	if anim_name.begins_with("cast"):
		return 9.0
	if anim_name.begins_with("death"):
		return 10.0
	if anim_name.begins_with("hurt"):
		return 9.0
	return 5.0


func anim_loops(anim_name: String) -> bool:
	return anim_name.begins_with("idle") or anim_name.begins_with("walk") or anim_name.begins_with("cast")


## Region of one frame on a character sheet.
func frame_rect(id: String, anim_name: String, frame: int) -> Rect2:
	var meta: Dictionary = manifest["characters"][id]
	var a: Dictionary = meta["anims"][anim_name]
	var fw: float = meta["frame_w"]
	var fh: float = meta["frame_h"]
	return Rect2((int(a["col"]) + frame) * fw, int(a["row"]) * fh, fw, fh)


func anim_count(id: String, anim_name: String) -> int:
	return int(manifest["characters"][id]["anims"][anim_name]["count"])


## SpriteFrames for a character id (average, puck, ghoul, ...).
func frames(id: String) -> SpriteFrames:
	if _frames.has(id):
		return _frames[id]
	var meta: Dictionary = manifest["characters"][id]
	var sheet := tex(id)
	var fw: int = meta["frame_w"]
	var fh: int = meta["frame_h"]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in meta["anims"]:
		var a: Dictionary = meta["anims"][anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, anim_name.begins_with("idle") or anim_name.begins_with("walk") or anim_name.begins_with("cast"))
		var speed := 5.0
		if anim_name.begins_with("walk"):
			speed = 13.0
		elif anim_name.begins_with("cast"):
			speed = 9.0
		elif anim_name.begins_with("death"):
			speed = 10.0
		elif anim_name.begins_with("hurt"):
			speed = 9.0
		sf.set_animation_speed(anim_name, speed)
		for i in int(a["count"]):
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2((int(a["col"]) + i) * fw, int(a["row"]) * fh, fw, fh)
			sf.add_frame(anim_name, at)
	_frames[id] = sf
	return sf


func foot_y(id: String) -> float:
	return float(manifest["characters"][id].get("foot_y", manifest["characters"][id]["frame_h"] - 3))


func frame_size(id: String) -> Vector2:
	var meta: Dictionary = manifest["characters"][id]
	return Vector2(meta["frame_w"], meta["frame_h"])


## Frames for an animated prop (campfire_0.., torch_0.., brazier_0..).
func prop_frames(base: String, count: int, fps: float) -> SpriteFrames:
	var key := "prop:" + base
	if _frames.has(key):
		return _frames[key]
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", fps)
	for i in count:
		sf.add_frame("default", prop("%s_%d" % [base, i]))
	_frames[key] = sf
	return sf


# ---------- HD concept-art characters (DorkTeach's art, see tools/artgen/import_concepts.py) ----------

var hd: Dictionary = {}


func _load_hd() -> void:
	if hd.is_empty() and FileAccess.file_exists("res://assets/hd.json"):
		hd = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hd.json"))


func hd_has(id: String) -> bool:
	_load_hd()
	return hd.get("characters", {}).has(id)


## Pose meta: {tex, foot:[x,y], w, h, faces}. Falls back to idle.
func hd_pose(id: String, pose: String) -> Dictionary:
	_load_hd()
	var poses: Dictionary = hd["characters"][id]["poses"]
	return poses.get(pose, poses["idle"])


func hd_has_pose(id: String, pose: String) -> bool:
	return hd_has(id) and hd["characters"][id]["poses"].has(pose)


func hd_walk_count(id: String) -> int:
	var n := 0
	while hd_has_pose(id, "walk%d" % n):
		n += 1
	return n


func portrait(id: String) -> Texture2D:
	return tex("portrait_" + id)


func portrait_framed(id: String) -> Texture2D:
	return tex("portrait_%s_framed" % id)


func icon(name: String) -> Texture2D:
	return tex("icon_" + name)


# ---------- HUD pieces from DorkTeach's HUD sheet (tools/artgen/import_hud.py) ----------

var ui_meta: Dictionary = {}


func ui(name: String) -> Texture2D:
	var key := "ui:" + name
	if not _tex.has(key):
		_tex[key] = load_png("res://assets/ui/%s.png" % name)
	return _tex[key]


func ui_info(name: String) -> Dictionary:
	if ui_meta.is_empty() and FileAccess.file_exists("res://assets/ui/ui.json"):
		ui_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/ui.json"))
	return ui_meta.get(name, {})


## Spell / blood effects cut from DorkTeach's FX sheets (tools/artgen/import_fx.py).
func fx(name: String) -> Texture2D:
	var key := "fx:" + name
	if not _tex.has(key):
		_tex[key] = load_png("res://assets/fx/%s.png" % name)
	return _tex[key]
