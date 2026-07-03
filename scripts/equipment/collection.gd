class_name Collection
extends RefCounted

const COLLECTION_KEY: String = "collection"


static func get_tracked_ids() -> Array[String]:
	return [
		"铁剑", "火焰剑", "战斧", "匕首", "毒匕首", "手枪", "冰霜枪", "火焰法杖",
		"铁盔", "皮帽", "铁甲", "皮衣", "铁手套", "护腕", "铁靴", "皮靴",
		"铜戒", "石符",
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


static func has_collected(name: String) -> bool:
	return get_collected().has(name)
