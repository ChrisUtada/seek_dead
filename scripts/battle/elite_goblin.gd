class_name EliteGoblin
extends EnemyBase

@export var config: EnemyConfig

@onready var ai: AIComponent = $AIComponent
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _hitbox: Hitbox = $MeleeHitbox

var _was_moving: bool = false
var _has_switched_to_flee: bool = false


func _ready():
	_enemy_ready()
	if config:
		apply_config(config)
		_apply_tier_multipliers(config)
		ai.apply_behavior_config(config)
	ai.attack_performed.connect(_on_ai_attack)
	ai.alerted.connect(_on_ai_alerted)
	ai.set_home(global_position, 600.0)
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_hitbox.lifespan = 0


func apply_config(cfg: EnemyConfig):
	_enemy_config = cfg
	state.max_hp = randf_range(cfg.hp_min, cfg.hp_max)
	state.hp = state.max_hp
	state.innate_type = cfg.innate_type
	state.defenses = cfg.defenses.duplicate()
	mover.speed = cfg.speed


func _on_ai_alerted(_target: Node2D):
	pass


func _on_ai_attack(target: Node2D, damage: float):
	if not is_instance_valid(target):
		return
	_hitbox.damage = damage
	_hitbox.damage_type = state.innate_type
	_hitbox.shooter = self
	_hitbox.knockback_force = 180.0
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

	if not _has_switched_to_flee and get_hp_ratio() < 0.3:
		_has_switched_to_flee = true
		ai.set_behaviors([AIComponent.BehaviorType.FLEE], [-1.0])

	if effects.has_effect(StatusEffect.EffectType.FREEZE):
		mover.apply_slow(0.4)
	else:
		mover.reset_speed_multiplier()

	if ai.is_attacking():
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
