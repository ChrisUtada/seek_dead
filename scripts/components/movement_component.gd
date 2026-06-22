class_name MovementComponent
extends Node

@export var speed: float = 200.0

var direction: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
var frozen: bool = false

var current_speed: float:
	get: return 0.0 if frozen else speed * speed_multiplier

func _physics_process(_delta):
	var parent: CharacterBody2D = get_parent()
	parent.velocity = direction * current_speed
	parent.move_and_slide()

func reset_speed_multiplier():
	speed_multiplier = 1.0

func apply_slow(mult: float):
	speed_multiplier = mult
