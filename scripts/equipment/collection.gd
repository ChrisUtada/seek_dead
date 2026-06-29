class_name Collection
extends RefCounted

const COLLECTION_KEY: String = "collection"


static func get_tracked_ids() -> Array[String]:
	return [
		"铁头盔", "布帽", "学徒兜帽",
		"铁甲", "皮甲", "锁子甲",
		"铁剑", "匕首", "木棍",
		"铁护手", "皮手套",
		"铁护腿", "皮靴",
		"铁戒指", "铜戒指",
		"魔法头盔", "稀有头盔", "传奇头盔",
		"魔法铁甲", "稀有铁甲", "传奇铁甲",
	]


static func get_collected() -> Dictionary:
	var data = SaveSystem.load_lobby_data()
	return data.get(COLLECTION_KEY, {})


static func _save_collected(collected: Dictionary):
	var data = SaveSystem.load_lobby_data()
	data[COLLECTION_KEY] = collected
	SaveSystem.save_lobby_data(data)


static func register_item(item: EquipmentBase):
	var collected = get_collected()
	var key = item.equipment_name
	if collected.has(key):
		return
	collected[key] = {
		"rarity": item.rarity,
		"slot": item.slot,
		"time": Time.get_datetime_string_from_system(),
	}
	_save_collected(collected)


static func get_collection_count() -> int:
	return get_collected().size()


static func get_total_count() -> int:
	return get_tracked_ids().size()


static func get_completion_percent() -> float:
	var total = get_tracked_ids().size()
	if total <= 0:
		return 1.0
	return float(get_collected().size()) / float(total)


static func get_global_bonuses() -> Dictionary:
	var count = get_collection_count()
	var bonuses: Dictionary = {}
	if count >= 5:
		bonuses["max_hp"] = 20
	if count >= 10:
		bonuses["move_speed"] = 0.05
	if count >= 15:
		bonuses["attack_damage"] = 5
	if count >= 20:
		bonuses["crit_rate"] = 0.03
	return bonuses


static func apply_global_bonuses(state: StateComponent):
	var bonuses = get_global_bonuses()
	for key in bonuses:
		var val = bonuses[key]
		match key:
			"max_hp":
				state.max_hp += val
				state.hp += val
			"move_speed":
				var ms = state.get("move_speed")
				state.set("move_speed", (ms if ms != null else 0.0) + val)
			"attack_damage":
				var ad = state.get("attack_damage")
				state.set("attack_damage", (ad if ad != null else 0.0) + val)
			"crit_rate":
				var cr = state.get("crit_rate")
				state.set("crit_rate", (cr if cr != null else 0.0) + val)


static func has_collected(name: String) -> bool:
	return get_collected().has(name)
