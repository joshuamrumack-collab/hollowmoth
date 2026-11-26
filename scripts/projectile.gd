extends Node2D
## Arrows, starknives and hush bolts. Hitting resolves through the shooter's PF1e strike().

var main: Node
var shooter: Combatant
var dir := Vector2.RIGHT
var speed := 300.0
var action: Dictionary = {}
var color := Color.WHITE
var pierce := false
var boomerang := false
var life := 1.2
var age := 0.0
var hit := {}
var returning := false


func _physics_process(delta: float) -> void:
	age += delta
	if not is_instance_valid(shooter):
		queue_free()
		return
	if boomerang and age > 0.4 and not returning:
		returning = true
		hit.clear()
	if returning and shooter != null:
		dir = (shooter.global_position + Vector2(0, -6) - global_position).normalized()
		if global_position.distance_to(shooter.global_position + Vector2(0, -6)) < 8.0:
			queue_free()
			return
	position += dir * speed * delta
	if age > life or main.blocked(position):
		queue_free()
		return
	for t in main.all_combatants():
		if t == shooter or t.is_dead() or hit.has(t):
			continue
		if not action.get("any_team", false) and t.team == shooter.team:
			continue
		if t.state == Combatant.State.DASH:
			continue
		var body: Vector2 = t.global_position + Vector2(0, -t.radius)
		if body.distance_to(global_position) <= t.radius + 3.0:
			hit[t] = true
			shooter.strike(t, action)
			Sfx.play("arrow_hit" if shooter.team == "hero" else "shock", global_position, -4.0)
			if shooter.has_method("on_projectile_hit"):
				shooter.on_projectile_hit(t, action)
			if not pierce and not boomerang:
				queue_free()
				return
	queue_redraw()


func _draw() -> void:
	if boomerang:
		var a := age * 20.0
		for i in 4:
			draw_line(Vector2.ZERO, Vector2.from_angle(a + i * PI / 2) * 3.0, color, 1.0)
	else:
		draw_line(-dir * 7.0, Vector2.ZERO, color.darkened(0.3), 1.0)
		draw_circle(Vector2.ZERO, 1.2, color)
