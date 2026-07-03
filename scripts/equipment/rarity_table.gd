class_name RarityTable
extends RefCounted


const AFFIX_COUNT: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: 1,
	EquipmentEnums.Rarity.RARE: 2,
	EquipmentEnums.Rarity.LEGENDARY: 3,
}

const AFFIX_LEVEL_RANGE: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: Vector2(1, 2),
	EquipmentEnums.Rarity.RARE: Vector2(2, 3),
	EquipmentEnums.Rarity.LEGENDARY: Vector2(3, 4),
}

const BASE_WEIGHTS: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: 60,
	EquipmentEnums.Rarity.RARE: 30,
	EquipmentEnums.Rarity.LEGENDARY: 10,
}

const BASE_STAT_MULTIPLIER: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: 1.0,
	EquipmentEnums.Rarity.RARE: 1.15,
	EquipmentEnums.Rarity.LEGENDARY: 1.3,
}


static func roll_rarity(quality_bonus: float = 0.0, force_min: int = -1) -> int:
	var weights = BASE_WEIGHTS.duplicate()
	if quality_bonus > 0:
		weights[EquipmentEnums.Rarity.MAGIC] = int(weights[EquipmentEnums.Rarity.MAGIC] * (1.0 - quality_bonus * 0.5))
		weights[EquipmentEnums.Rarity.RARE] = int(weights[EquipmentEnums.Rarity.RARE] * (1.0 + quality_bonus))
		weights[EquipmentEnums.Rarity.LEGENDARY] = max(1, int(weights[EquipmentEnums.Rarity.LEGENDARY] + quality_bonus * 15))
	var total = 0
	for r in weights.values():
		total += r
	if total <= 0:
		return EquipmentEnums.Rarity.MAGIC
	var roll = randi() % total
	var cumulative = 0
	for r in [EquipmentEnums.Rarity.LEGENDARY, EquipmentEnums.Rarity.RARE, EquipmentEnums.Rarity.MAGIC]:
		cumulative += weights[r]
		if roll < cumulative:
			if force_min >= 0 and r < force_min:
				continue
			return r
	return EquipmentEnums.Rarity.MAGIC


static func get_affix_count(rarity: int) -> int:
	return AFFIX_COUNT.get(rarity, 0)


static func get_affix_level_range(rarity: int) -> Vector2:
	return AFFIX_LEVEL_RANGE.get(rarity, Vector2(0, 0))


static func get_rarity_name(rarity: int) -> String:
	return EquipmentEnums.RARITY_NAMES.get(rarity, "未知")


static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		EquipmentEnums.Rarity.MAGIC: return Color(0.3, 0.6, 1.0)
		EquipmentEnums.Rarity.RARE: return Color(1.0, 0.8, 0.2)
		EquipmentEnums.Rarity.LEGENDARY: return Color(1.0, 0.3, 0.1)
		_: return Color(0.8, 0.8, 0.8)


static func get_base_stat_multiplier(rarity: int) -> float:
	return BASE_STAT_MULTIPLIER.get(rarity, 1.0)
