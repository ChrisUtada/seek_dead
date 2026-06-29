class_name RarityTable
extends RefCounted


const AFFIX_COUNT: Dictionary = {
	EquipmentEnums.Rarity.COMMON: 0,
	EquipmentEnums.Rarity.MAGIC: 1,
	EquipmentEnums.Rarity.RARE: 2,
	EquipmentEnums.Rarity.LEGENDARY: 3,
	EquipmentEnums.Rarity.SET: 2,
}

const AFFIX_LEVEL_RANGE: Dictionary = {
	EquipmentEnums.Rarity.COMMON: Vector2(0, 0),
	EquipmentEnums.Rarity.MAGIC: Vector2(1, 2),
	EquipmentEnums.Rarity.RARE: Vector2(2, 3),
	EquipmentEnums.Rarity.LEGENDARY: Vector2(3, 4),
	EquipmentEnums.Rarity.SET: Vector2(2, 3),
}

const BASE_WEIGHTS: Dictionary = {
	EquipmentEnums.Rarity.COMMON: 60,
	EquipmentEnums.Rarity.MAGIC: 25,
	EquipmentEnums.Rarity.RARE: 12,
	EquipmentEnums.Rarity.LEGENDARY: 3,
	EquipmentEnums.Rarity.SET: 0,
}

const BASE_STAT_MULTIPLIER: Dictionary = {
	EquipmentEnums.Rarity.COMMON: 1.0,
	EquipmentEnums.Rarity.MAGIC: 1.15,
	EquipmentEnums.Rarity.RARE: 1.35,
	EquipmentEnums.Rarity.LEGENDARY: 1.6,
	EquipmentEnums.Rarity.SET: 2.0,
}


static func roll_rarity(quality_bonus: float = 0.0, force_min: int = -1) -> int:
	var weights = BASE_WEIGHTS.duplicate()
	if quality_bonus > 0:
		weights[EquipmentEnums.Rarity.COMMON] = int(weights[EquipmentEnums.Rarity.COMMON] * (1.0 - quality_bonus))
		weights[EquipmentEnums.Rarity.MAGIC] = int(weights[EquipmentEnums.Rarity.MAGIC] * (1.0 + quality_bonus))
		weights[EquipmentEnums.Rarity.RARE] = int(weights[EquipmentEnums.Rarity.RARE] * (1.0 + quality_bonus * 2))
		weights[EquipmentEnums.Rarity.LEGENDARY] = max(1, int(weights[EquipmentEnums.Rarity.LEGENDARY] + quality_bonus * 10))
		if quality_bonus >= 0.3:
			weights[EquipmentEnums.Rarity.SET] = max(1, int(quality_bonus * 10))
	var total = 0
	for r in weights.values():
		total += r
	if total <= 0:
		return EquipmentEnums.Rarity.COMMON
	var roll = randi() % total
	var cumulative = 0
	for r in [EquipmentEnums.Rarity.SET, EquipmentEnums.Rarity.LEGENDARY, EquipmentEnums.Rarity.RARE, EquipmentEnums.Rarity.MAGIC, EquipmentEnums.Rarity.COMMON]:
		cumulative += weights[r]
		if roll < cumulative:
			if force_min >= 0 and r < force_min:
				continue
			return r
	return EquipmentEnums.Rarity.COMMON


static func get_affix_count(rarity: int) -> int:
	return AFFIX_COUNT.get(rarity, 0)


static func get_affix_level_range(rarity: int) -> Vector2:
	return AFFIX_LEVEL_RANGE.get(rarity, Vector2(0, 0))


static func get_rarity_name(rarity: int) -> String:
	return EquipmentEnums.RARITY_NAMES.get(rarity, "未知")


static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		EquipmentEnums.Rarity.COMMON: return Color(0.8, 0.8, 0.8)
		EquipmentEnums.Rarity.MAGIC: return Color(0.3, 0.6, 1.0)
		EquipmentEnums.Rarity.RARE: return Color(1.0, 0.8, 0.2)
		EquipmentEnums.Rarity.LEGENDARY: return Color(1.0, 0.3, 0.1)
		EquipmentEnums.Rarity.SET: return Color(0.3, 1.0, 0.3)
	return Color.WHITE


static func get_base_stat_multiplier(rarity: int) -> float:
	return BASE_STAT_MULTIPLIER.get(rarity, 1.0)
