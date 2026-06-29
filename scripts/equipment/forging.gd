class_name Forging
extends RefCounted


const UPGRADE_COST: Dictionary = {
	EquipmentEnums.Rarity.COMMON: { "iron": 3, "gold": 20 },
	EquipmentEnums.Rarity.MAGIC: { "iron": 8, "magic_essence": 2, "gold": 50 },
	EquipmentEnums.Rarity.RARE: { "iron": 15, "magic_essence": 5, "legendary_core": 1, "gold": 150 },
}

const UPGRADE_CHANCE: Dictionary = {
	EquipmentEnums.Rarity.COMMON: 0.9,
	EquipmentEnums.Rarity.MAGIC: 0.7,
	EquipmentEnums.Rarity.RARE: 0.4,
}

const ENCHANT_COST: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: { "magic_essence": 1, "gold": 30 },
	EquipmentEnums.Rarity.RARE: { "magic_essence": 3, "gold": 80 },
	EquipmentEnums.Rarity.LEGENDARY: { "magic_essence": 6, "legendary_core": 1, "gold": 200 },
}

const REROLL_COST: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: { "iron": 5, "gold": 40 },
	EquipmentEnums.Rarity.RARE: { "iron": 10, "magic_essence": 2, "gold": 100 },
	EquipmentEnums.Rarity.LEGENDARY: { "iron": 20, "magic_essence": 5, "gold": 250 },
}

const NEXT_RARITY: Dictionary = {
	EquipmentEnums.Rarity.COMMON: EquipmentEnums.Rarity.MAGIC,
	EquipmentEnums.Rarity.MAGIC: EquipmentEnums.Rarity.RARE,
	EquipmentEnums.Rarity.RARE: EquipmentEnums.Rarity.LEGENDARY,
}

const RARITY_PREFIX: Dictionary = {
	EquipmentEnums.Rarity.COMMON: "",
	EquipmentEnums.Rarity.MAGIC: "魔法",
	EquipmentEnums.Rarity.RARE: "稀有",
	EquipmentEnums.Rarity.LEGENDARY: "传奇",
	EquipmentEnums.Rarity.SET: "套装",
}


static func can_upgrade(item: EquipmentBase) -> bool:
	var next = NEXT_RARITY.get(item.rarity, -1)
	if next < 0:
		return false
	var cost = UPGRADE_COST.get(item.rarity, {})
	return ForgeMaterial.has_materials(cost)


static func do_upgrade(item: EquipmentBase) -> bool:
	var next = NEXT_RARITY.get(item.rarity, -1)
	if next < 0:
		return false
	var cost = UPGRADE_COST.get(item.rarity, {})
	if not ForgeMaterial.spend_materials(cost):
		return false
	var chance = UPGRADE_CHANCE.get(item.rarity, 0.0)
	if randf() <= chance:
		item.rarity = next
		if not RARITY_PREFIX.get(next, "").is_empty():
			item.equipment_name = RARITY_PREFIX[next] + item.equipment_name
		return true
	else:
		if item.rarity == EquipmentEnums.Rarity.COMMON:
			return false
		var prev = item.rarity - 1
		item.rarity = prev
		return false


static func can_enchant(item: EquipmentBase) -> bool:
	var max_affixes = RarityTable.get_affix_count(item.rarity)
	if item.affixes.size() >= max_affixes:
		return false
	var cost = ENCHANT_COST.get(item.rarity, {})
	if cost.is_empty():
		return false
	return ForgeMaterial.has_materials(cost)


static func do_enchant(item: EquipmentBase) -> bool:
	var max_affixes = RarityTable.get_affix_count(item.rarity)
	if item.affixes.size() >= max_affixes:
		return false
	var cost = ENCHANT_COST.get(item.rarity, {})
	if cost.is_empty() or not ForgeMaterial.spend_materials(cost):
		return false
	var level_range = RarityTable.get_affix_level_range(item.rarity)
	var affix = AffixDatabase.random_affix(int(level_range.x), int(level_range.y), item.affixes)
	if not affix:
		return false
	item.affixes.append(affix.duplicate(true))
	return true


static func can_reroll(item: EquipmentBase) -> bool:
	var cost = REROLL_COST.get(item.rarity, {})
	if cost.is_empty():
		return false
	return ForgeMaterial.has_materials(cost)


static func do_reroll(item: EquipmentBase) -> bool:
	var cost = REROLL_COST.get(item.rarity, {})
	if cost.is_empty() or not ForgeMaterial.spend_materials(cost):
		return false
	var level_range = RarityTable.get_affix_level_range(item.rarity)
	var count = item.affixes.size()
	var new_affixes: Array[Affix] = []
	for i in range(count):
		var affix = AffixDatabase.random_affix(int(level_range.x), int(level_range.y), new_affixes)
		if affix:
			new_affixes.append(affix.duplicate(true))
	item.affixes = new_affixes
	return true


static func do_dismantle(item: EquipmentBase) -> Dictionary:
	if item.rarity >= EquipmentEnums.Rarity.COMMON and item.rarity <= EquipmentEnums.Rarity.LEGENDARY:
		var yield_data = ForgeMaterial.dismantle_yield(item.rarity)
		ForgeMaterial.add_materials(yield_data)
		return yield_data
	return {}
