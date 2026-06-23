class_name SprintComponent
extends Node

signal sprint_started()
signal sprint_finished()

@export var speed_multiplier: float = 1.5
@export var stamina_cost_per_second: float = 10.0

var is_sprinting: bool = false

func try_start_sprint():
	if is_sprinting:
		return
	var parent = get_parent()
	var state = parent.state
	if state.stamina < stamina_cost_per_second:
		return
	is_sprinting = true
	parent.mover.speed_multiplier = speed_multiplier
	sprint_started.emit()

func stop_sprint():
	if not is_sprinting:
		return
	is_sprinting = false
	get_parent().mover.reset_speed_multiplier()
	sprint_finished.emit()

func _process(delta: float):
	if is_sprinting:
		var parent = get_parent()
		var state = parent.state
		if not state.consume_stamina(stamina_cost_per_second * delta):
			stop_sprint()
