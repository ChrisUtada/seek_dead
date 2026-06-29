class_name ForgeMaterial
extends RefCounted

enum MaterialType {
	GOLD,
	IRON_SHARD,
	MAGIC_ESSENCE,
	LEGENDARY_CORE,
}

const MATERIAL_NAMES: Dictionary = {
	MaterialType.GOLD: "金币",
	MaterialType.IRON_SHARD: "铁碎片",
	MaterialType.MAGIC_ESSENCE: "魔法精华",
	MaterialType.LEGENDARY_CORE: "传奇核心",
}

const MATERIAL_COLORS: Dictionary = {
	MaterialType.GOLD: Color(1, 0.85, 0.3),
	MaterialType.IRON_SHARD: Color(0.6, 0.6, 0.7),
	MaterialType.MAGIC_ESSENCE: Color(0.4, 0.5, 1),
	MaterialType.LEGENDARY_CORE: Color(1, 0.4, 0.2),
}


static func get_lobby_data_key(t: int) -> String:
	match t:
		MaterialType.GOLD: return "gold"
		MaterialType.IRON_SHARD: return "iron"
		MaterialType.MAGIC_ESSENCE: return "magic_essence"
		MaterialType.LEGENDARY_CORE: return "legendary_core"
	return ""


static func has_materials(costs: Dictionary) -> bool:
	var data = SaveSystem.load_lobby_data()
	for key in costs:
		if data.get(key, 0) < costs[key]:
			return false
	return true


static func spend_materials(costs: Dictionary) -> bool:
	if not has_materials(costs):
		return false
	var data = SaveSystem.load_lobby_data()
	for key in costs:
		data[key] = data.get(key, 0) - costs[key]
	SaveSystem.save_lobby_data(data)
	return true


static func add_materials(rewards: Dictionary):
	var data = SaveSystem.load_lobby_data()
	for key in rewards:
		data[key] = data.get(key, 0) + rewards[key]
	SaveSystem.save_lobby_data(data)


static func dismantle_yield(rarity: int) -> Dictionary:
	match rarity:
		EquipmentEnums.Rarity.COMMON:
			return { "iron": 2 }
		EquipmentEnums.Rarity.MAGIC:
			return { "iron": 5, "magic_essence": 1 }
		EquipmentEnums.Rarity.RARE:
			return { "iron": 10, "magic_essence": 3, "gold": 50 }
		EquipmentEnums.Rarity.LEGENDARY:
			return { "iron": 20, "magic_essence": 8, "legendary_core": 1, "gold": 200 }
		EquipmentEnums.Rarity.SET:
			return { "iron": 15, "magic_essence": 5, "gold": 100 }
	return { "iron": 1 }
