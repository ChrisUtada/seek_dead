extends CharacterBody2D

@onready var state: StateComponent = $StateComponent
@onready var _sprite: Sprite2D = $Sprite2D

var _flash_timer: float = 0.0
var _effects: Array[StatusEffect] = []
var _current_tint: Color = Color(1, 1, 1)

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

func take_damage(amount: float, damage_type: int):
	var result = state.take_damage(amount, damage_type)
	var hit_str = DamageSystem.hit_result_to_string(result.hit_result)
	var prefix = "[%s]" % hit_str if hit_str else ""
	print("敌人受伤: %s %.0f (剩余HP: %.0f/%.0f)" % [prefix, result.final_damage, state.hp, state.max_hp])
	_flash_timer = 0.1
	return result

func apply_status(effect_type: int, damage: float, duration: float):
	if effect_type < 0 or effect_type >= StatusEffect.EffectType.size():
		return

	for e in _effects:
		if e.effect_type == effect_type:
			e.remaining = max(e.remaining, duration)
			return

	var effect = StatusEffect.new()
	effect.effect_type = effect_type
	effect.damage_per_tick = damage
	effect.duration = duration
	effect.remaining = duration
	effect.damage_type = _effect_type_to_damage_type(effect_type)
	effect.target_node = self
	add_child(effect)
	_effects.append(effect)

	print("  状态施加: %s (%.1f秒, 每跳%.0f伤害)" % [_effect_name(effect_type), duration, damage])
	_update_tint()

func _effect_type_to_damage_type(et: int) -> int:
	match et:
		StatusEffect.EffectType.POISON: return DamageSystem.DamageType.POISON
		StatusEffect.EffectType.BURN: return DamageSystem.DamageType.FIRE
		StatusEffect.EffectType.BLEED: return DamageSystem.DamageType.SLASH
		_: return -1

func _remove_effect(idx: int):
	var name_str = _effect_name(_effects[idx].effect_type)
	_effects[idx].queue_free()
	_effects.remove_at(idx)
	print("  状态结束: %s" % name_str)
	_update_tint()

func _effect_name(et: int) -> String:
	match et:
		StatusEffect.EffectType.POISON: return "中毒"
		StatusEffect.EffectType.BURN: return "燃烧"
		StatusEffect.EffectType.FREEZE: return "冰冻"
		StatusEffect.EffectType.STUN: return "眩晕"
		StatusEffect.EffectType.SLOW: return "减速"
		StatusEffect.EffectType.BLEED: return "流血"
		StatusEffect.EffectType.REGEN: return "再生"
	return "未知"

func _update_tint():
	if _effects.is_empty():
		_current_tint = Color(1, 1, 1)
	else:
		_current_tint = _effects[-1].get_color()
	if _flash_timer <= 0:
		_sprite.modulate = _current_tint

func _on_died():
	print("敌人死亡!")
	queue_free()

func _physics_process(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			_sprite.modulate = _current_tint

	var i = _effects.size() - 1
	while i >= 0:
		if not _effects[i].process(delta):
			_remove_effect(i)
		i -= 1

	var target = _find_nearest_player()
	if target and global_position.distance_to(target.global_position) > 30:
		var speed = 20.0 if _has_status(StatusEffect.EffectType.FREEZE) else 50.0
		var dir = global_position.direction_to(target.global_position)
		velocity = dir * speed
		move_and_slide()

func _has_status(et: int) -> bool:
	for e in _effects:
		if e.effect_type == et:
			return true
	return false

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return null
	return players[0]
