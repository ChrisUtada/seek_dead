class_name EquipmentDrop
extends RefCounted

const SLOT_NAMES: Array = [
	"主手武器", "副手武器", "头盔", "身体", "手部", "腿部", "饰品1", "饰品2",
]
const RARITY_PREFIX: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: "精良",
	EquipmentEnums.Rarity.RARE: "稀有",
	EquipmentEnums.Rarity.LEGENDARY: "传奇",
}
const DEFAULT_POOL: EquipmentPool = preload("res://resources/equipment_pool/default.tres")


static func generate_drop(quality_bonus: float = 0.0, slot: int = -1, force_min_rarity: int = -1, template: EquipmentTemplate = null) -> EquipmentBase:
	var equip = EquipmentBase.new()
	equip.rarity = RarityTable.roll_rarity(quality_bonus, force_min_rarity)
	if template == null:
		template = DEFAULT_POOL.roll()
	if template == null:
		return equip
	equip.slot = template.slot
	if template.weapon_data:
		var wd = template.weapon_data.duplicate(true) as WeaponData
		wd.damage *= RarityTable.get_base_stat_multiplier(equip.rarity)
		equip.weapon_data = wd
	var prefix = RARITY_PREFIX.get(equip.rarity, "")
	equip.equipment_name = prefix + template.template_name if prefix else template.template_name
	_add_affixes(equip)
	_try_apply_set_label(equip)
	return equip


static func generate_drops(count: int, quality_bonus: float = 0.0, force_min_rarity: int = -1) -> Array[EquipmentBase]:
	var result: Array[EquipmentBase] = []
	for i in range(count):
		result.append(generate_drop(quality_bonus, -1, force_min_rarity))
	return result


static func _add_affixes(equip: EquipmentBase):
	var count = RarityTable.get_affix_count(equip.rarity)
	var level_range = RarityTable.get_affix_level_range(equip.rarity)
	var all_affixes = AffixDatabase.get_all_affixes()
	if all_affixes.is_empty():
		return
	var picked: Array[Affix] = []
	var pool = all_affixes.duplicate()
	pool = pool.filter(func(a): return a.can_appear_on(equip.slot))
	pool.shuffle()
	for i in range(min(count, pool.size())):
		var aff = pool[i].duplicate()
		aff.level = int(randf_range(level_range.x, level_range.y + 0.99))
		_scale_affix_values(aff)
		picked.append(aff)
	equip.affixes = picked


static func _scale_affix_values(aff: Affix):
	var mult = 1.0 + (aff.level - 1) * 0.25
	for m in aff.stat_modifiers:
		m.value *= mult
	for e in aff.trigger_effects:
		e.param_value *= mult
	for c in aff.conditional_bonuses:
		if c.bonus:
			c.bonus.value *= mult


static func _try_apply_set_label(equip: EquipmentBase):
	var all_sets = SetDatabase.get_all_sets()
	if all_sets.is_empty():
		return
	if randf() > 0.1:
		return
	var set_def = all_sets[randi() % all_sets.size()]
	equip.set_id = set_def.set_id
	equip.equipment_name = set_def.set_name + _slot_suffix(equip.slot)


static func _slot_suffix(slot: int) -> String:
	match slot:
		EquipmentEnums.EquipmentSlot.WEAPON_MAIN: return "主武"
		EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND: return "副武"
		EquipmentEnums.EquipmentSlot.HELMET: return "头盔"
		EquipmentEnums.EquipmentSlot.BODY: return "战甲"
		EquipmentEnums.EquipmentSlot.HAND: return "手套"
		EquipmentEnums.EquipmentSlot.LEG: return "战靴"
		EquipmentEnums.EquipmentSlot.ACCESSORY_1: return "戒指"
		EquipmentEnums.EquipmentSlot.ACCESSORY_2: return "护符"
		_: return "装备"
