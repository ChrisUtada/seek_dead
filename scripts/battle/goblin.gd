extends EnemyBase

const _AIComp = preload("res://scripts/components/ai_component.gd")

@export var config: EnemyConfig

@onready var ai: AIComponent = $AIComponent
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _was_moving: bool = false

@onready var _hitbox: Hitbox = $MeleeHitbox


func _ready():
	_enemy_ready()
	if config:
		apply_config(config)
	ai.attack_performed.connect(_on_ai_attack)
	ai.alerted.connect(_on_ai_alerted)
	ai.set_home(global_position, 600.0)
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_hitbox.lifespan = 0


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
	_hitbox.damage = damage
	_hitbox.damage_type = state.innate_type
	_hitbox.shooter = self
	_hitbox.knockback_force = 120.0
	_hitbox.reset()
	_hitbox.global_position = global_position
	_hitbox.monitoring = true
	_hitbox.monitorable = true
	var timer = get_tree().create_timer(0.15, false)
	timer.timeout.connect(func():
		_hitbox.monitoring = false
		_hitbox.monitorable = false
	)


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

	_update_facing()
	_update_animation()


func _update_facing():
	var target = ai.get_target()
	if target and is_instance_valid(target):
		_sprite.flip_h = target.global_position.x < global_position.x
	elif mover.direction.length() > 0.1:
		_sprite.flip_h = mover.direction.x < 0


func _update_animation():
	if _anim == null:
		return
	var is_moving = mover.direction.length() > 0.1
	if is_moving and not _was_moving:
		if _anim.has_animation("run"):
			_anim.play("run")
	elif not is_moving and _was_moving:
		_anim.stop()
	_was_moving = is_moving
