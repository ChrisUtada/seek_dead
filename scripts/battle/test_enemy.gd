extends CharacterBody2D

const _SEComp = preload("res://scripts/components/status_effect_component.gd")
const _AIComp = preload("res://scripts/components/ai_component.gd")
const _MoverComp = preload("res://scripts/components/movement_component.gd")

@onready var state: StateComponent = $StateComponent
@onready var effects: StatusEffectComponent = $StatusEffectComponent
@onready var ai: AIComponent = $AIComponent
@onready var mover: MovementComponent = $MovementComponent
@onready var _sprite: Sprite2D = $Sprite2D

var _flash_timer: float = 0.0

func _ready():
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
	state.died.connect(_on_died)
	effects.tick_damage.connect(_on_tick_damage)
	effects.effect_applied.connect(_on_effect_applied)
	effects.effect_expired.connect(_on_effect_expired)
	mover.speed = 50.0

func take_damage(amount: float, damage_type: int):
	var result = state.take_damage(amount, damage_type)
	var hit_str = DamageSystem.hit_result_to_string(result.hit_result)
	var prefix = "[%s]" % hit_str if hit_str else ""
	print("敌人受伤: %s %.0f (剩余HP: %.0f/%.0f)" % [prefix, result.final_damage, state.hp, state.max_hp])
	_flash_timer = 0.1
	return result

func apply_status(effect_type: int, damage: float, duration: float):
	effects.apply(effect_type, damage, duration)

func _on_tick_damage(dmg: float, dmg_type: int):
	take_damage(dmg, dmg_type)

func _on_effect_applied(_et: int, name_str: String):
	_update_tint()
	print("  状态施加: %s" % name_str)

func _on_effect_expired(_et: int, name_str: String):
	_update_tint()
	print("  状态结束: %s" % name_str)

func _update_tint():
	var c = effects.get_last_color() if effects.has_any() else Color(1, 1, 1)
	if _flash_timer <= 0:
		_sprite.modulate = c

func _on_died():
	print("敌人死亡!")
	queue_free()

func _physics_process(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			_update_tint()

	effects.update(delta)
	ai.process_ai(delta)

	if effects.has_effect(StatusEffect.EffectType.FREEZE):
		mover.apply_slow(0.4)
	else:
		mover.reset_speed_multiplier()

	if ai.get_target() == null or ai.is_player_in_attack_range():
		mover.direction = Vector2.ZERO
	else:
		mover.direction = ai.get_move_direction()
