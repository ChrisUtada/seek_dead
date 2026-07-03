class_name EquipmentDrop
extends RefCounted

const SLOT_NAMES: Array = [
	"主手武器", "副手武器", "头盔", "身体", "手部", "腿部", "饰品1", "饰品2",
]
const BASE_NAMES: Dictionary = {
	EquipmentEnums.EquipmentSlot.WEAPON_MAIN: ["铁剑", "短弓", "法杖"],
	EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND: ["铁剑", "短弓", "法杖"],
	EquipmentEnums.EquipmentSlot.HELMET: ["铁盔", "皮帽", "头带"],
	EquipmentEnums.EquipmentSlot.BODY: ["铁甲", "皮衣", "布袍"],
	EquipmentEnums.EquipmentSlot.HAND: ["铁手套", "护腕", "指虎"],
	EquipmentEnums.EquipmentSlot.LEG: ["铁靴", "皮靴", "布鞋"],
	EquipmentEnums.EquipmentSlot.ACCESSORY_1: ["铜戒", "石符", "骨环"],
	EquipmentEnums.EquipmentSlot.ACCESSORY_2: ["铜戒", "石符", "骨环"],
}
const RARITY_PREFIX: Dictionary = {
	EquipmentEnums.Rarity.MAGIC: "精良",
	EquipmentEnums.Rarity.RARE: "稀有",
	EquipmentEnums.Rarity.LEGENDARY: "传奇",
}

const WEAPON_TEMPLATES: Array = [
	preload("res://resources/weapon_templates/iron_sword.tres"),
	preload("res://resources/weapon_templates/dagger.tres"),
	preload("res://resources/weapon_templates/battle_axe.tres"),
	preload("res://resources/weapon_templates/fire_sword.tres"),
	preload("res://resources/weapon_templates/pistol.tres"),
	preload("res://resources/weapon_templates/ice_gun.tres"),
	preload("res://resources/weapon_templates/poison_dagger.tres"),
	preload("res://resources/weapon_templates/flame_staff.tres"),
]


static func generate_drop(quality_bonus: float = 0.0, slot: int = -1, force_min_rarity: int = -1) -> EquipmentBase:
	var rarity = RarityTable.roll_rarity(quality_bonus, force_min_rarity)
	var equip = EquipmentBase.new()
	equip.rarity = rarity
	if slot < 0:
		slot = randi() % 8
	equip.slot = slot
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN or slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		equip.weapon_data = _generate_weapon_data(equip)
		equip.equipment_name = _weapon_name(equip)
	else:
		equip.equipment_name = _build_name(equip)
	_add_affixes(equip)
	_try_apply_set_label(equip)
	return equip


static func _generate_weapon_data(equip: EquipmentBase) -> WeaponData:
	var pool = WEAPON_TEMPLATES
	if equip.slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		pool = pool.filter(func(t): return t.can_dual_wield)
		if pool.is_empty():
			pool = WEAPON_TEMPLATES
	var template = pool[randi() % pool.size()] as WeaponData
	var wd = template.duplicate(true) as WeaponData
	var mult = RarityTable.get_base_stat_multiplier(equip.rarity)
	wd.damage *= mult
	return wd


static func _weapon_name(equip: EquipmentBase) -> String:
	var wd = equip.weapon_data
	if not wd or wd.weapon_name.is_empty():
		return _build_name(equip)
	var prefix = RARITY_PREFIX.get(equip.rarity, "")
	if prefix == "":
		return wd.weapon_name
	return prefix + wd.weapon_name


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
