extends "res://scripts/battle/enemy_base.gd"

const _AIComp = preload("res://scripts/components/ai_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

@onready var ai: AIComponent = $AIComponent

func _ready():
	_enemy_ready()
	_apply_random_config()
	ai.attack_performed.connect(_on_ai_attack)
	ai.alerted.connect(_on_ai_alerted)
	ai.set_home(global_position, 600.0)
	mover.speed = 50.0

func _on_ai_alerted(_target: Node2D):
	pass

func _apply_random_config():
	var hp_val = randi_range(50, 150)
	state.max_hp = hp_val
	state.hp = hp_val
	state.innate_type = randi_range(0, DamageSystem.DamageType.size() - 1)
	state.defenses = {
		"puncture_defense": randf_range(0.0, 0.3),
		"slash_defense": randf_range(0.0, 0.3),
		"smash_defense": randf_range(0.0, 0.3),
		"fire_defense": randf_range(0.0, 0.3),
	}

func apply_config(config: EnemyConfig):
	state.max_hp = randf_range(config.hp_min, config.hp_max)
	state.hp = state.max_hp
	state.innate_type = config.innate_type
	state.defenses = config.defenses.duplicate()
	mover.speed = config.speed
	_generate_texture(config.color, 32)

func _on_ai_attack(target: Node2D, damage: float):
	if not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(damage, state.innate_type)
	if target.has_method("knockback"):
		var dir = (target.global_position - global_position).normalized()
		target.knockback(dir * 120.0)
	AudioManager.play_sfx(AudioManager.SfxType.ENEMY_ATTACK)
	print("敌人攻击! 造成 %.0f 伤害" % damage)

func _on_died():
	print("敌人死亡!")
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
