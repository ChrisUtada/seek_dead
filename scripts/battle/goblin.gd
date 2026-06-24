extends EnemyBase

const _AIComp = preload("res://scripts/components/ai_component.gd")

@onready var ai: AIComponent = $AIComponent
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _was_moving: bool = false


func _ready():
	_enemy_ready()
	ai.attack_performed.connect(_on_ai_attack)
	ai.alerted.connect(_on_ai_alerted)
	ai.set_home(global_position, 600.0)


func apply_config(config: EnemyConfig):
	state.max_hp = randf_range(config.hp_min, config.hp_max)
	state.hp = state.max_hp
	state.innate_type = config.innate_type
	state.defenses = config.defenses.duplicate()
	mover.speed = config.speed


func _on_ai_alerted(_target: Node2D):
	pass


func _on_ai_attack(target: Node2D, damage: float):
	if not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(damage, state.innate_type)
	if target.has_method("knockback"):
		var dir = (target.global_position - global_position).normalized()
		target.knockback(dir * 120.0)


func _on_died():
	super()


func _physics_process(delta):
	_enemy_physics(delta)
	effects.update(delta)
	ai.process_ai(delta)

	if effects.has_effect(StatusEffect.EffectType.FREEZE):
		mover.apply_slow(0.4)
	else:
		mover.reset_speed_multiplier()

	if ai.current_state == AIComponent.AIState.ATTACK:
		mover.direction = Vector2.ZERO
	else:
		mover.direction = ai.get_move_direction()

	_update_animation()


func _update_animation():
	if _anim == null:
		return
	var is_moving = mover.direction.length() > 0.1
	if is_moving and not _was_moving:
		_anim.play("run")
	elif not is_moving and _was_moving:
		_anim.stop()
	_was_moving = is_moving
