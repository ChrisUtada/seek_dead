class_name CombatStats
extends RefCounted

## 战斗属性（类型安全替代 DamageSystem 旧式无类型 Dictionary）
##
## 旧代码用 {"puncture_bonus": .., "fire_defense": .., "crit_rate": ..} 这种无类型
## Dictionary 在攻击方/防御方之间传递属性，键名拼写错误只能在运行时暴露。
## CombatStats 把全部字段提升为强类型成员，并在 from_dict 中对未知键发出
## Debug.warn 告警，从而在加载/换装时即可发现拼写错误。

# ── 攻击加成（按伤害类型，0.0 起） ──
var puncture_bonus: float = 0.0
var slash_bonus: float = 0.0
var smash_bonus: float = 0.0
var fire_bonus: float = 0.0
var lightning_bonus: float = 0.0
var ice_bonus: float = 0.0
var poison_bonus: float = 0.0
var wind_bonus: float = 0.0

# ── 防御减免（按伤害类型，0.0 ~ 0.85） ──
var puncture_defense: float = 0.0
var slash_defense: float = 0.0
var smash_defense: float = 0.0
var fire_defense: float = 0.0
var lightning_defense: float = 0.0
var ice_defense: float = 0.0
var poison_defense: float = 0.0
var wind_defense: float = 0.0

# ── 暴击与属性 ──
var crit_rate: float = 0.05
var crit_damage: float = 1.5
var innate_type: int = -1


# 从旧式 Dictionary 构建（兼容 .tres / EnemyConfig.defenses / 装备加成 bonuses）。
# 未知键会被 Debug.warn 提示以捕获拼写错误，不会崩溃。
static func from_dict(d: Dictionary) -> CombatStats:
	var cs := CombatStats.new()
	for key in d.keys():
		match key:
			"puncture_bonus": cs.puncture_bonus = float(d[key])
			"slash_bonus": cs.slash_bonus = float(d[key])
			"smash_bonus": cs.smash_bonus = float(d[key])
			"fire_bonus": cs.fire_bonus = float(d[key])
			"lightning_bonus": cs.lightning_bonus = float(d[key])
			"ice_bonus": cs.ice_bonus = float(d[key])
			"poison_bonus": cs.poison_bonus = float(d[key])
			"wind_bonus": cs.wind_bonus = float(d[key])
			"puncture_defense": cs.puncture_defense = float(d[key])
			"slash_defense": cs.slash_defense = float(d[key])
			"smash_defense": cs.smash_defense = float(d[key])
			"fire_defense": cs.fire_defense = float(d[key])
			"lightning_defense": cs.lightning_defense = float(d[key])
			"ice_defense": cs.ice_defense = float(d[key])
			"poison_defense": cs.poison_defense = float(d[key])
			"wind_defense": cs.wind_defense = float(d[key])
			"crit_rate": cs.crit_rate = float(d[key])
			"crit_damage": cs.crit_damage = float(d[key])
			"innate_type": cs.innate_type = int(d[key])
			_: Debug.warn("[CombatStats] 未识别的属性键: \"%s\"（已忽略，请检查拼写）" % key)
	return cs


func bonus_for(dt: DamageSystem.DamageType) -> float:
	match dt:
		DamageSystem.DamageType.PUNCTURE: return puncture_bonus
		DamageSystem.DamageType.SLASH: return slash_bonus
		DamageSystem.DamageType.SMASH: return smash_bonus
		DamageSystem.DamageType.FIRE: return fire_bonus
		DamageSystem.DamageType.LIGHTNING: return lightning_bonus
		DamageSystem.DamageType.ICE: return ice_bonus
		DamageSystem.DamageType.POISON: return poison_bonus
		DamageSystem.DamageType.WIND: return wind_bonus
	return 0.0


func defense_for(dt: DamageSystem.DamageType) -> float:
	match dt:
		DamageSystem.DamageType.PUNCTURE: return puncture_defense
		DamageSystem.DamageType.SLASH: return slash_defense
		DamageSystem.DamageType.SMASH: return smash_defense
		DamageSystem.DamageType.FIRE: return fire_defense
		DamageSystem.DamageType.LIGHTNING: return lightning_defense
		DamageSystem.DamageType.ICE: return ice_defense
		DamageSystem.DamageType.POISON: return poison_defense
		DamageSystem.DamageType.WIND: return wind_defense
	return 0.0
