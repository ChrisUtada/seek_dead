# ⚠️ 死代码 / 预留（Phase D 死代码治理）：
# 本文件定义的是「原实时武器 · 词缀系统」的枚举与显示名（装备槽 / 稀有度 / 触发事件 /
# 特效动作 / 条件 / 词缀目标等），【老虎机对决流程完全不使用】这些装备槽 / 稀有度 / 触发链体系。
# 仅 stat_modifier.gd 引用了其中的 StatTarget / ModifierType（stat_modifier 自身也是未接线预留）。
# 保留于此以备 Phase F 词缀系统复用；请勿将其误认为活跃逻辑，也不要在此新增老虎机相关内容。
class_name EquipmentEnums
extends RefCounted

enum EquipmentSlot { WEAPON_MAIN, WEAPON_OFFHAND, HELMET, BODY, HAND, LEG, ACCESSORY_1, ACCESSORY_2 }
enum Rarity { COMMON, MAGIC, RARE, LEGENDARY, SET }
enum ModifierType { ADD, MUL, OVERRIDE }

enum StatTarget {
	MAX_HP,
	HP_REGEN,
	MAX_ENERGY,
	ENERGY_REGEN,
	MAX_STAMINA,
	STAMINA_REGEN,
	MOVE_SPEED,
	ATTACK_SPEED,
	ATTACK_DAMAGE,
	CRIT_RATE,
	CRIT_DAMAGE,
	PUNCTURE_DEF,
	SLASH_DEF,
	SMASH_DEF,
	FIRE_DEF,
	LIGHTNING_DEF,
	ICE_DEF,
	POISON_DEF,
	WIND_DEF,
	PUNCTURE_BONUS,
	SLASH_BONUS,
	SMASH_BONUS,
	FIRE_BONUS,
	LIGHTNING_BONUS,
	ICE_BONUS,
	POISON_BONUS,
	WIND_BONUS,
	DODGE_COOLDOWN,
	DODGE_DISTANCE,
	HEAT_PER_ATTACK,
	HEAT_COOLING,
}

const SLOT_NAMES: Dictionary = {
	EquipmentSlot.WEAPON_MAIN: "主手武器",
	EquipmentSlot.WEAPON_OFFHAND: "副手武器",
	EquipmentSlot.HELMET: "头盔",
	EquipmentSlot.BODY: "身体",
	EquipmentSlot.HAND: "手部",
	EquipmentSlot.LEG: "腿部",
	EquipmentSlot.ACCESSORY_1: "饰品1",
	EquipmentSlot.ACCESSORY_2: "饰品2",
}

const RARITY_NAMES: Dictionary = {
	Rarity.COMMON: "普通",
	Rarity.MAGIC: "魔法",
	Rarity.RARE: "稀有",
	Rarity.LEGENDARY: "传奇",
	Rarity.SET: "套装",
}

enum TriggerEvent {
	ON_HIT,
	ON_KILL,
	ON_HURT,
	ON_DODGE,
	ON_CRIT,
	ON_SKILL_USE,
	ON_MELTDOWN,
	ON_ROOM_CLEAR,
	ON_EMPTY_AMMO,
	ON_RELOAD,
	ON_STATUS_INFLICT,
	ON_PICKUP,
}

enum EffectAction {
	EXPLODE,
	SPAWN_PROJECTILE,
	SPAWN_POOL,
	CHAIN_LIGHTNING,
	HEAL,
	SHIELD,
	STATUS_INFLICT,
	FIRE_AURA,
	SUMMON,
	KNOCKBACK,
	TELEPORT,
	SLOW_ENEMIES,
	DODGE_RESET,
}

enum ConditionType {
	HP_ABOVE,
	HP_BELOW,
	ENEMIES_NEARBY,
	STAMINA_FULL,
	HEAT_ABOVE,
	STATUS_ON_SELF,
	STATUS_ON_ENEMY,
	NO_AMMO,
	AFTER_DODGE,
	AFTER_SKILL,
	COMBO_COUNT,
}
