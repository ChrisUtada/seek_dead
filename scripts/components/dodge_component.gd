class_name DodgeComponent
extends Node

signal dodge_started(direction: Vector2)
signal dodge_finished()

@export var dodge_distance: float = 150.0
@export var dodge_duration: float = 0.2
@export var dodge_cooldown: float = 0.5
@export var stamina_cost: float = 15.0
@export var heat_reduction: float = 15.0

var is_dodging: bool = false
var _cooldown_timer: float = 0.0

func can_dodge() -> bool:
	return _cooldown_timer <= 0.0 and not is_dodging

func try_dodge(direction: Vector2):
	if not can_dodge():
		return
	var parent = get_parent()
	var state = parent.state
	if not state.consume_stamina(stamina_cost):
		return
	is_dodging = true
	_cooldown_timer = dodge_cooldown
	parent.is_invincible = true
	if not state.in_meltdown() and state.heat > 0:
		state.heat -= heat_reduction
	var start_pos = parent.global_position
	var end_pos = start_pos + direction * dodge_distance
	var tween = create_tween()
	tween.tween_property(parent, "global_position", end_pos, dodge_duration)
	tween.tween_callback(_finish_dodge)
	dodge_started.emit(direction)

func _finish_dodge():
	is_dodging = false
	get_parent().is_invincible = false
	dodge_finished.emit()

func _process(delta: float):
	if _cooldown_timer > 0:
		_cooldown_timer -= delta
