extends Node2D
## Floating combat text and barks.

var text := ""
var color := Color.WHITE
var life := 0.8
var age := 0.0
var size := 8


func _process(delta: float) -> void:
	age += delta
	position.y -= 14.0 * delta
	if age >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var a: float = clamp(1.0 - (age - life * 0.6) / (life * 0.4), 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color(0, 0, 0, a))
	draw_string(font, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color.r, color.g, color.b, a))
