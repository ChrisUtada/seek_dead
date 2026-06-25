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
	var p = get_parent()
	var dmg = p as Damageable
	if not dmg:
		return
	var state = p.state
	if not state.consume_stamina(stamina_cost):
		return
	is_dodging = true
	_cooldown_timer = dodge_cooldown
	dmg.is_invincible = true
	AudioManager.play_sfx(AudioManager.SfxType.PLAYER_DODGE)
	if not state.in_meltdown() and state.heat > 0:
		state.heat -= heat_reduction
	var tween = create_tween()
	tween.tween_property(p, "global_position", p.global_position + direction * dodge_distance, dodge_duration)
	tween.tween_callback(_finish_dodge.bind(p))
	dodge_started.emit(direction)

func _finish_dodge(p: Node):
	is_dodging = false
	var dmg = p as Damageable
	if dmg:
		dmg.is_invincible = false
	dodge_finished.emit()

func _process(delta: float):
	if _cooldown_timer > 0:
		_cooldown_timer -= delta
