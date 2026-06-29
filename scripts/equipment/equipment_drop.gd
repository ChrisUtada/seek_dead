class_name EquipmentDrop
extends RefCounted

const SLOT_NAMES: Array = [
	"武器", "头盔", "身体", "手部", "腿部", "饰品1", "饰品2",
]
const BASE_NAMES: Dictionary = {
	EquipmentEnums.EquipmentSlot.WEAPON: ["铁剑", "短弓", "法杖"],
	EquipmentEnums.EquipmentSlot.HELMET: ["铁盔", "皮帽", "头带"],
	EquipmentEnums.EquipmentSlot.BODY: ["铁甲", "皮衣", "布袍"],
	EquipmentEnums.EquipmentSlot.HAND: ["铁手套", "护腕", "指虎"],
	EquipmentEnums.EquipmentSlot.LEG: ["铁靴", "皮靴", "布鞋"],
	EquipmentEnums.EquipmentSlot.ACCESSORY_1: ["铜戒", "石符", "骨环"],
	EquipmentEnums.EquipmentSlot.ACCESSORY_2: ["铜戒", "石符", "骨环"],
}
const RARITY_PREFIX: Dictionary = {
	EquipmentEnums.Rarity.COMMON: "",
	EquipmentEnums.Rarity.MAGIC: "精良",
	EquipmentEnums.Rarity.RARE: "稀有",
	EquipmentEnums.Rarity.LEGENDARY: "传奇",
	EquipmentEnums.Rarity.SET: "套装",
}


static func generate_drop(quality_bonus: float = 0.0, slot: int = -1, force_min_rarity: int = -1) -> EquipmentBase:
	var rarity = RarityTable.roll_rarity(quality_bonus, force_min_rarity)
	if slot < 0:
		slot = randi() % 7
	var equip = EquipmentBase.new()
	equip.slot = slot
	equip.rarity = rarity
	equip.equipment_name = _build_name(equip)
	if rarity != EquipmentEnums.Rarity.COMMON:
		_add_affixes(equip)
	return equip


static func generate_drops(count: int, quality_bonus: float = 0.0, force_min_rarity: int = -1) -> Array[EquipmentBase]:
	var result: Array[EquipmentBase] = []
	for i in range(count):
		result.append(generate_drop(quality_bonus, -1, force_min_rarity))
	return result


static func _build_name(equip: EquipmentBase) -> String:
	var base_pool = BASE_NAMES.get(equip.slot, ["未知"])
	var base_name = base_pool[randi() % base_pool.size()]
	var prefix = RARITY_PREFIX.get(equip.rarity, "")
	if prefix == "":
		return base_name
	return prefix + base_name


static func _add_affixes(equip: EquipmentBase):
	var count = RarityTable.get_affix_count(equip.rarity)
	var level_range = RarityTable.get_affix_level_range(equip.rarity)
	var all_affixes = AffixDatabase.get_all_affixes()
	if all_affixes.is_empty():
		return
	var picked: Array[Affix] = []
	var pool = all_affixes.duplicate()
	pool.shuffle()
	for i in range(min(count, pool.size())):
		var aff = pool[i]
		picked.append(aff)
	equip.affixes = picked
