class_name AffixDatabase
extends RefCounted

const SLOT_WEAPON := [0, 1]
const SLOT_DEFENSE := [2, 3]
const SLOT_MOBILITY := [4, 5]


static func get_all_affixes() -> Array[Affix]:
	return [
		_numeric_1(), _numeric_2(), _numeric_3(), _numeric_4(), _numeric_5(),
		_numeric_6(), _numeric_7(), _numeric_8(), _numeric_9(), _numeric_10(),
		_trigger_11(), _trigger_12(), _trigger_13(), _trigger_14(), _trigger_15(),
		_trigger_16(), _trigger_17(), _trigger_18(), _trigger_19(), _trigger_20(),
		_trigger_21(), _trigger_22(),
		_condition_23(), _condition_24(), _condition_25(), _condition_26(),
		_condition_27(), _condition_28(), _condition_29(), _condition_30(),
	]


static func get_affix(name: String) -> Affix:
	for a in get_all_affixes():
		if a.affix_name == name:
			return a
	return null


static func _sm(target: int, type: int, val: float) -> StatModifier:
	var m = StatModifier.new()
	m.target_stat = target
	m.modifier_type = type
	m.value = val
	return m


static func _te(event: int, action: int, chance: float, val: float, cd: float = 0.0) -> TriggerEffect:
	var e = TriggerEffect.new()
	e.trigger_event = event
	e.effect_action = action
	e.chance = chance
	e.param_value = val
	e.cooldown = cd
	return e


static func _cb(cond: int, cond_val: float, mod: StatModifier) -> ConditionalBonus:
	var c = ConditionalBonus.new()
	c.condition = cond
	c.condition_value = cond_val
	c.bonus = mod
	return c


static func _affix(name: String, desc: String, mods: Array = [], triggers: Array = [], conds: Array = [], slots: Array = []) -> Affix:
	var a = Affix.new()
	a.affix_name = name
	a.affix_description = desc
	a.stat_modifiers = mods
	a.trigger_effects = triggers
	a.conditional_bonuses = conds
	a.allowed_slots = slots
	return a


static func _numeric_1() -> Affix:
	return _affix("铁壁", "全防御 +0.15", [
		_sm(EquipmentEnums.StatTarget.PUNCTURE_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.SLASH_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.SMASH_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.FIRE_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.LIGHTNING_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.ICE_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.POISON_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
		_sm(EquipmentEnums.StatTarget.WIND_DEF, EquipmentEnums.ModifierType.ADD, 0.15),
	], [], [], SLOT_DEFENSE)

static func _numeric_2() -> Affix:
	return _affix("狂怒", "攻击伤害 +25%", [
		_sm(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.25),
	], [], [], SLOT_WEAPON)

static func _numeric_3() -> Affix:
	return _affix("疾风", "攻击速度 +20%", [
		_sm(EquipmentEnums.StatTarget.ATTACK_SPEED, EquipmentEnums.ModifierType.MUL, 0.20),
	], [], [], SLOT_WEAPON)

static func _numeric_4() -> Affix:
	return _affix("活力", "HP上限 +80", [
		_sm(EquipmentEnums.StatTarget.MAX_HP, EquipmentEnums.ModifierType.ADD, 80.0),
	], [], [], SLOT_DEFENSE)

static func _numeric_5() -> Affix:
	return _affix("再生", "HP回复 +5/秒", [
		_sm(EquipmentEnums.StatTarget.HP_REGEN, EquipmentEnums.ModifierType.ADD, 5.0),
	], [], [], SLOT_DEFENSE)

static func _numeric_6() -> Affix:
	return _affix("灵巧", "暴击率 +8%", [
		_sm(EquipmentEnums.StatTarget.CRIT_RATE, EquipmentEnums.ModifierType.ADD, 0.08),
	], [], [], SLOT_WEAPON)

static func _numeric_7() -> Affix:
	return _affix("致命", "暴击伤害 +0.5x", [
		_sm(EquipmentEnums.StatTarget.CRIT_DAMAGE, EquipmentEnums.ModifierType.ADD, 0.5),
	], [], [], SLOT_WEAPON)

static func _numeric_8() -> Affix:
	return _affix("迅捷", "移动速度 +20%", [
		_sm(EquipmentEnums.StatTarget.MOVE_SPEED, EquipmentEnums.ModifierType.MUL, 0.20),
	], [], [], SLOT_WEAPON + SLOT_MOBILITY)

static func _numeric_9() -> Affix:
	return _affix("神行", "闪避距离+30% / 冷却-0.2s", [
		_sm(EquipmentEnums.StatTarget.DODGE_DISTANCE, EquipmentEnums.ModifierType.MUL, 0.30),
		_sm(EquipmentEnums.StatTarget.DODGE_COOLDOWN, EquipmentEnums.ModifierType.ADD, -0.2),
	], [], [], SLOT_WEAPON + SLOT_MOBILITY)

static func _numeric_10() -> Affix:
	return _affix("元素专精", "火焰伤害+40% / 雷电伤害+40%", [
		_sm(EquipmentEnums.StatTarget.FIRE_BONUS, EquipmentEnums.ModifierType.ADD, 0.40),
		_sm(EquipmentEnums.StatTarget.LIGHTNING_BONUS, EquipmentEnums.ModifierType.ADD, 0.40),
	], [], [], SLOT_WEAPON)


static func _trigger_11() -> Affix:
	return _affix("灼烧", "命中时25%额外火焰伤害", [], [
		_te(EquipmentEnums.TriggerEvent.ON_HIT, EquipmentEnums.EffectAction.EXPLODE, 0.25, 100.0),
	], [], SLOT_WEAPON)

static func _trigger_12() -> Affix:
	return _affix("冰爆", "击杀时100%冻结周围", [], [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.EXPLODE, 1.0, 100.0),
	], [], SLOT_WEAPON)

static func _trigger_13() -> Affix:
	return _affix("毒雾", "击杀时30%生成毒池3s", [], [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.SPAWN_POOL, 0.30, 5.0),
	], [], SLOT_WEAPON)

static func _trigger_14() -> Affix:
	return _affix("连锁闪电", "暴击时40%连锁3个敌人", [], [
		_te(EquipmentEnums.TriggerEvent.ON_CRIT, EquipmentEnums.EffectAction.CHAIN_LIGHTNING, 0.40, 1.0, 3.0),
	], [], SLOT_WEAPON)

static func _trigger_15() -> Affix:
	return _affix("嗜血", "击杀时20%回复10%HP", [], [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.HEAL, 0.20, 0.0),
	], [], SLOT_WEAPON)

static func _trigger_16() -> Affix:
	return _affix("震荡", "命中时15%击退周围", [], [
		_te(EquipmentEnums.TriggerEvent.ON_HIT, EquipmentEnums.EffectAction.KNOCKBACK, 0.15, 200.0),
	], [], SLOT_WEAPON)

static func _trigger_17() -> Affix:
	return _affix("生命护盾", "受伤时100%获得护盾(CD5s)", [], [
		_te(EquipmentEnums.TriggerEvent.ON_HURT, EquipmentEnums.EffectAction.SHIELD, 1.0, 0.0, 5.0),
	], [], SLOT_DEFENSE)

static func _trigger_18() -> Affix:
	return _affix("弹药循环", "击杀时40%回复弹药", [], [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.HEAL, 0.40, 3.0),
	], [], SLOT_WEAPON)

static func _trigger_19() -> Affix:
	return _affix("超载爆发", "进入超载时释放冲击波", [], [
		_te(EquipmentEnums.TriggerEvent.ON_MELTDOWN, EquipmentEnums.EffectAction.EXPLODE, 1.0, 200.0),
	], [], SLOT_WEAPON)

static func _trigger_20() -> Affix:
	return _affix("能量回转", "使用技能时50%回复15%能量", [], [
		_te(EquipmentEnums.TriggerEvent.ON_SKILL_USE, EquipmentEnums.EffectAction.HEAL, 0.50, 15.0),
	], [], SLOT_WEAPON)

static func _trigger_21() -> Affix:
	return _affix("闪避反击", "闪避时100%发射4枚投射物(CD1s)", [], [
		_te(EquipmentEnums.TriggerEvent.ON_DODGE, EquipmentEnums.EffectAction.SPAWN_PROJECTILE, 1.0, 4.0, 1.0),
	], [], SLOT_WEAPON + SLOT_MOBILITY)

static func _trigger_22() -> Affix:
	return _affix("收割", "击杀时100%减少技能冷却0.5s", [], [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.HEAL, 1.0, 0.0),
	], [], SLOT_WEAPON)


static func _condition_23() -> Affix:
	return _affix("背水一战", "HP<30%时伤害+80%移速+30%", [], [], [
		_cb(EquipmentEnums.ConditionType.HP_BELOW, 0.3, _sm(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.80)),
	], SLOT_WEAPON)

static func _condition_24() -> Affix:
	return _affix("满体力加攻", "体力全满时攻击速度+30%", [], [], [
		_cb(EquipmentEnums.ConditionType.STAMINA_FULL, 0.0, _sm(EquipmentEnums.StatTarget.ATTACK_SPEED, EquipmentEnums.ModifierType.MUL, 0.30)),
	], SLOT_WEAPON + SLOT_MOBILITY)

static func _condition_25() -> Affix:
	return _affix("过热狂暴", "热量>70时暴击率+20%", [], [], [
		_cb(EquipmentEnums.ConditionType.HEAT_ABOVE, 0.7, _sm(EquipmentEnums.StatTarget.CRIT_RATE, EquipmentEnums.ModifierType.ADD, 0.20)),
	], SLOT_WEAPON)

static func _condition_26() -> Affix:
	return _affix("残血护盾", "HP<20%时获得护盾(CD8s)", [], [], [
		_cb(EquipmentEnums.ConditionType.HP_BELOW, 0.2, _sm(EquipmentEnums.StatTarget.MAX_HP, EquipmentEnums.ModifierType.OVERRIDE, 30.0)),
	], SLOT_DEFENSE)

static func _condition_27() -> Affix:
	return _affix("弹尽粮绝", "弹药=0时远程伤害+100%", [], [], [
		_cb(EquipmentEnums.ConditionType.NO_AMMO, 0.0, _sm(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 1.0)),
	], SLOT_WEAPON)

static func _condition_28() -> Affix:
	return _affix("追猎", "周围200px内有敌人时移速+25%", [], [], [
		_cb(EquipmentEnums.ConditionType.ENEMIES_NEARBY, 200.0, _sm(EquipmentEnums.StatTarget.MOVE_SPEED, EquipmentEnums.ModifierType.MUL, 0.25)),
	], SLOT_WEAPON + SLOT_MOBILITY)

static func _condition_29() -> Affix:
	return _affix("毒刃", "目标中毒时伤害+50%", [], [], [
		_cb(EquipmentEnums.ConditionType.STATUS_ON_ENEMY, 0.0, _sm(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.50)),
	], SLOT_WEAPON)

static func _condition_30() -> Affix:
	return _affix("冰甲", "自身有冻结状态时受到伤害-40%", [], [], [
		_cb(EquipmentEnums.ConditionType.STATUS_ON_SELF, 0.0, _sm(EquipmentEnums.StatTarget.FIRE_DEF, EquipmentEnums.ModifierType.ADD, 0.40)),
	], SLOT_DEFENSE)
