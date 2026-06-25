class_name StatusEffectComponent
extends Node

signal tick_damage(damage: float, damage_type: int)
signal effect_applied(effect_type: int, name: String)
signal effect_expired(effect_type: int, name: String)

var effects: Array[StatusEffect] = []

func apply(effect_type: int, damage: float, duration: float):
	if effect_type < 0 or effect_type >= StatusEffect.EffectType.size():
		return

	for e in effects:
		if e.effect_type == effect_type:
			e.remaining = max(e.remaining, duration)
			return

	var effect = StatusEffect.new()
	effect.effect_type = effect_type
	effect.damage_per_tick = damage
	effect.duration = duration
	effect.remaining = duration
	effect.tick_timer = 1.0
	effect.damage_type = _effect_type_to_damage_type(effect_type)
	effects.append(effect)
	effect_applied.emit(effect_type, effect.get_display_name())

func update(delta):
	var i = effects.size() - 1
	while i >= 0:
		if not effects[i].update(delta):
			effect_expired.emit(effects[i].effect_type, effects[i].get_display_name())
			effects.remove_at(i)
		elif effects[i].is_tick_ready():
			var dmg = effects[i].get_tick_damage()
			effects[i].reset_tick()
			tick_damage.emit(dmg, effects[i].damage_type)
		i -= 1

func has_effect(effect_type: int) -> bool:
	for e in effects:
		if e.effect_type == effect_type:
			return true
	return false

func has_any() -> bool:
	return not effects.is_empty()

func get_last_color() -> Color:
	if effects.is_empty():
		return Color(1, 1, 1)
	return effects[-1].get_color()

func _effect_type_to_damage_type(et: int) -> int:
	match et:
		StatusEffect.EffectType.POISON: return DamageSystem.DamageType.POISON
		StatusEffect.EffectType.BURN: return DamageSystem.DamageType.FIRE
		StatusEffect.EffectType.BLEED: return DamageSystem.DamageType.SLASH
		_: return -1


