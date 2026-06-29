class_name EquipmentEnums
extends RefCounted

enum EquipmentSlot { WEAPON, HELMET, BODY, HAND, LEG, ACCESSORY_1, ACCESSORY_2 }
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
	EquipmentSlot.WEAPON: "武器",
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
