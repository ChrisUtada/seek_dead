extends EnemyBase

const _BulletScene = preload("res://scenes/battle/projectile.tscn")
const _DefaultBulletData = preload("res://resources/bullets/default_bullet.tres")

@export var config: EnemyConfig

@onready var ai: AIComponent = $AIComponent
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _was_moving: bool = false


func _ready():
	_enemy_ready()
	if config:
		apply_config(config)
		_apply_tier_multipliers(config)
	ai.attack_range = 200.0
	ai.attack_performed.connect(_on_ai_attack)
	ai.set_home(global_position, 600.0)
	ai.set_behaviors(
		[AIComponent.BehaviorType.STRAFE, AIComponent.BehaviorType.RETREAT, AIComponent.BehaviorType.SUMMON],
		[4.0, 3.0, -1.0]
	)


func apply_config(cfg: EnemyConfig):
	state.max_hp = randf_range(cfg.hp_min, cfg.hp_max)
	state.hp = state.max_hp
	state.innate_type = cfg.innate_type
	state.defenses = cfg.defenses.duplicate()
	mover.speed = cfg.speed


func _on_ai_attack(target: Node2D, damage: float):
	if not is_instance_valid(target):
		return
	if not ai.has_line_of_sight_to(target, 400.0):
		return
	var dir = global_position.direction_to(target.global_position)
	var bullet = _BulletScene.instantiate()
	bullet.direction = dir
	bullet.global_position = global_position + dir * 24
	bullet.damage = damage
	bullet.damage_type = state.innate_type
	bullet.shooter = self
	bullet.data = config.bullet_data if config and config.bullet_data else _DefaultBulletData
	get_parent().add_child(bullet)
	_setup_fireball_visual(bullet)


func _setup_fireball_visual(bullet):
	var spr = bullet.get_node_or_null("Sprite2D")
	if spr:
		spr.texture = DamageSystem.get_circle_texture(10, Color(1, 0.6, 0.1), Color(1, 0.9, 0.4))
		spr.centered = true


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
