class_name SkillBase
extends Resource

@export var skill_name: String = "Skill"
@export var skill_description: String = ""
@export var energy_cost: float = 20.0
@export var cooldown: float = 5.0
@export var duration: float = 0.0

var cooldown_timer: float = 0.0
var is_active: bool = false

func can_use(energy: float) -> bool:
	return cooldown_timer <= 0.0 and energy >= energy_cost

func use(user: Node2D) -> bool:
	var state = user.get_node("StateComponent")
	if not can_use(state.energy):
		return false
	state.energy -= energy_cost
	cooldown_timer = cooldown
	if duration > 0:
		is_active = true
		_activate_skill(user)
		var timer = user.get_tree().create_timer(duration)
		timer.timeout.connect(_on_skill_finished.bind(user))
	else:
		_activate_skill(user)
		_on_skill_finished(user)
	return true

func _activate_skill(_user: Node2D):
	pass

func _on_skill_finished(_user: Node2D):
	is_active = false

func tick(delta: float):
	if cooldown_timer > 0:
		cooldown_timer -= delta

func get_cooldown_ratio() -> float:
	return cooldown_timer / cooldown if cooldown > 0 else 0.0
