class_name SkillBase
extends Resource

@export var skill_name: String = "Skill"
@export var skill_description: String = ""
@export var energy_cost: float = 20.0
@export var cooldown: float = 5.0
@export var duration: float = 0.0
@export var level: int = 1
@export var cast_color: Color = Color(1, 1, 1)
@export var cast_radius: float = 0.0
@export var cast_duration: float = 0.3
@export var cast_type: String = "ring"
var max_level: int = 4

var cooldown_timer: float = 0.0
var is_active: bool = false

func can_use(state: StateComponent) -> bool:
	return cooldown_timer <= 0.0 and state.energy >= energy_cost

func use(user: Node2D) -> bool:
	var state = user.get("state") as StateComponent
	if not state or not can_use(state):
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

func play_visual(user: Node2D):
	if cast_radius <= 0:
		return
	var world = user.get_parent()
	if not world:
		return
	var vfx = ColorRect.new()
	vfx.size = Vector2(cast_radius * 2, cast_radius * 2)
	vfx.position = Vector2(-cast_radius, -cast_radius)
	vfx.color = Color(cast_color.r, cast_color.g, cast_color.b, 0.5)
	vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(vfx)
	vfx.global_position = user.global_position
	if cast_type == "ring":
		var tween = user.create_tween()
		tween.tween_property(vfx, "scale", Vector2(1.5, 1.5), cast_duration)
		tween.parallel().tween_property(vfx, "modulate", Color(cast_color.r, cast_color.g, cast_color.b, 0), cast_duration)
		tween.tween_callback(vfx.queue_free)
	else:
		var tween = user.create_tween()
		tween.tween_property(vfx, "modulate", Color(cast_color.r, cast_color.g, cast_color.b, 0), cast_duration)
		tween.tween_callback(vfx.queue_free)


func _activate_skill(_user: Node2D):
	pass


func _on_skill_finished(_user: Node2D):
	is_active = false

func tick(delta: float):
	if cooldown_timer > 0:
		cooldown_timer -= delta

func get_cooldown_ratio() -> float:
	return cooldown_timer / cooldown if cooldown > 0 else 0.0
