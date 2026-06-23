class_name MovementComponent
extends Node

@export var speed: float = 200.0

var direction: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
var frozen: bool = false

var current_speed: float:
	get: return 0.0 if frozen else speed * speed_multiplier

var _push_velocity: Vector2 = Vector2.ZERO
var _push_duration: float = 0.0

func push(velocity: Vector2, duration: float = 0.15):
	_push_velocity = velocity
	_push_duration = duration

func _physics_process(_delta):
	var parent: CharacterBody2D = get_parent()
	var vel = Vector2.ZERO
	if _push_duration > 0:
		_push_duration -= _delta
		var weight = _push_duration / 0.15
		vel = _push_velocity * weight
		if _push_duration <= 0:
			_push_velocity = Vector2.ZERO
	if direction.length() > 0:
		vel += direction * current_speed
	parent.velocity = vel
	parent.move_and_slide()

func reset_speed_multiplier():
	speed_multiplier = 1.0

func apply_slow(mult: float):
	speed_multiplier = mult
