class_name DoorMarker
extends Area2D

enum Direction { UP, DOWN, LEFT, RIGHT }

@export var direction: Direction = Direction.RIGHT:
	set(v):
		direction = v
		queue_redraw()

signal player_entered(door_direction: int)

var locked: bool = true

@onready var _visual: Sprite2D = $Visual


func _ready():
	body_entered.connect(_on_body_entered)
	_update_visual()


func _on_body_entered(body: Node2D):
	if locked:
		return
	if body.is_in_group("player"):
		player_entered.emit(direction)


func unlock():
	locked = false
	_update_visual()


func lock():
	locked = true
	_update_visual()


func _update_visual():
	if not _visual:
		return
	if locked:
		_visual.modulate = Color(1, 0.2, 0.2, 0.7)
	else:
		_visual.modulate = Color(0.3, 1, 0.3, 0.4)


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