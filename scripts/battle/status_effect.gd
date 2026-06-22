class_name StatusEffect
extends Node

enum EffectType {
	POISON,
	BURN,
	FREEZE,
	STUN,
	SLOW,
	BLEED,
	REGEN
}

signal expired(effect_type: int, target: Node)

var effect_type: int
var damage_per_tick: float = 0.0
var tick_interval: float = 1.0
var duration: float = 3.0
var remaining: float = 0.0
var tick_timer: float = 0.0
var slow_amount: float = 0.0
var target_node: Node = null
var damage_type: int = -1

static func create_poison(damage: float, dur: float = 4.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.POISON
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.damage_type = DamageSystem.DamageType.POISON
	return e

static func create_burn(damage: float, dur: float = 3.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.BURN
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.damage_type = DamageSystem.DamageType.FIRE
	return e

static func create_bleed(damage: float, dur: float = 5.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.BLEED
	e.damage_per_tick = damage
	e.duration = dur
	e.remaining = dur
	e.damage_type = DamageSystem.DamageType.SLASH
	return e

static func create_stun(dur: float = 2.0) -> StatusEffect:
	var e = StatusEffect.new()
	e.effect_type = EffectType.STUN
	e.duration = dur
	e.remaining = dur
	return e

func _ready():
	tick_timer = tick_interval

func process(delta: float) -> bool:
	if remaining <= 0:
		return false

	remaining -= delta
	tick_timer -= delta

	if tick_timer <= 0 and target_node != null and damage_per_tick > 0:
		tick_timer = tick_interval
		if target_node.has_method("take_damage"):
			var dmg = DamageSystem.calculate_simple(damage_per_tick, damage_type)
			target_node.take_damage(dmg, damage_type)

	if remaining <= 0:
		expired.emit(effect_type, target_node)
		return false

	return true

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
