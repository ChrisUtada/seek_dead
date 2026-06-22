class_name StatusEffect
extends RefCounted

enum EffectType {
	POISON,
	BURN,
	FREEZE,
	STUN,
	SLOW,
	BLEED,
	REGEN
}

var effect_type: int
var damage_per_tick: float = 0.0
var tick_interval: float = 1.0
var duration: float = 3.0
var remaining: float = 0.0
var tick_timer: float = 0.0
var damage_type: int

static func create_poison(damage: float, dur: float = 4.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.POISON
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.tick_timer = 1.0
	e.damage_type = DamageSystem.DamageType.POISON
	return e

static func create_burn(damage: float, dur: float = 3.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.BURN
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.tick_timer = 1.0
	e.damage_type = DamageSystem.DamageType.FIRE
	return e

static func create_bleed(damage: float, dur: float = 5.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.BLEED
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.tick_timer = 1.0
	e.damage_type = DamageSystem.DamageType.SLASH
	return e

static func create_stun(dur: float = 2.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.STUN
	e.duration = dur
	e.remaining = dur
	e.tick_timer = 1.0
	e.damage_type = -1
	return e

func update(delta: float) -> bool:
	if remaining <= 0:
		return false
	remaining -= delta
	tick_timer -= delta
	return true

func is_tick_ready() -> bool:
	return tick_timer <= 0 and damage_per_tick > 0

func reset_tick():
	tick_timer = tick_interval

func get_tick_damage() -> float:
	return DamageSystem.calculate_simple(damage_per_tick, damage_type)

func get_display_name() -> String:
	match effect_type:
		EffectType.POISON: return "中毒"
		EffectType.BURN: return "燃烧"
		EffectType.FREEZE: return "冰冻"
		EffectType.STUN: return "眩晕"
		EffectType.SLOW: return "减速"
		EffectType.BLEED: return "流血"
		EffectType.REGEN: return "再生"
	return "未知"

func get_color() -> Color:
	match effect_type:
		EffectType.POISON: return Color(0.4, 1.0, 0.4)
		EffectType.BURN: return Color(1.0, 0.4, 0.1)
		EffectType.FREEZE: return Color(0.4, 0.8, 1.0)
		EffectType.STUN: return Color(1.0, 1.0, 0.4)
		EffectType.SLOW: return Color(0.6, 0.6, 1.0)
		EffectType.BLEED: return Color(1.0, 0.2, 0.2)
		EffectType.REGEN: return Color(0.4, 1.0, 0.4)
	return Color.WHITE
