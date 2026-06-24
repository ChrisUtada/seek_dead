extends Marker2D

enum Direction { UP, DOWN, LEFT, RIGHT }

@export var direction: Direction = Direction.RIGHT:
	set(v):
		direction = v
		queue_redraw()

func _draw():
	if not Engine.is_editor_hint():
		return
	var color = Color(0, 1, 0, 0.8)
	var len = 16.0
	var dir_vec: Vector2
	match direction:
		Direction.UP: dir_vec = Vector2.UP
		Direction.DOWN: dir_vec = Vector2.DOWN
		Direction.LEFT: dir_vec = Vector2.LEFT
		Direction.RIGHT: dir_vec = Vector2.RIGHT
	var tip = dir_vec * len
	var shaft = dir_vec * len * 0.5
	var perp = dir_vec.rotated(deg_to_rad(90)) * 4
	draw_line(Vector2.ZERO, shaft, color, 2)
	draw_line(tip, shaft + perp, color, 2)
	draw_line(tip, shaft - perp, color, 2)
	draw_circle(Vector2.ZERO, 3, color)
