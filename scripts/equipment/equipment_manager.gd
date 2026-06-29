class_name EquipmentManager
extends Node

const _SlotEnum = EquipmentEnums.EquipmentSlot
const _RarityEnum = EquipmentEnums.Rarity

signal equipment_equipped(slot: int, item: EquipmentBase)
signal equipment_unequipped(slot: int)

var _equipped: Dictionary = {}

func equip(item: EquipmentBase):
	var slot = item.slot
	unequip(slot)
	_equipped[slot] = item
	_apply_modifiers(item.stat_modifiers)
	EventManager.equipment_changed.emit(slot, item)
	equipment_equipped.emit(slot, item)


func unequip(slot: int):
	var old = _equipped.get(slot) as EquipmentBase
	if not old:
		return
	_remove_modifiers(old.stat_modifiers)
	_equipped.erase(slot)
	EventManager.equipment_changed.emit(slot, null)
	equipment_unequipped.emit(slot)


func get_equipped(slot: int) -> EquipmentBase:
	return _equipped.get(slot) as EquipmentBase


func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


func _get_state() -> StateComponent:
	var p = get_parent()
	if not p:
		return null
	return p.get_node_or_null("StateComponent") as StateComponent


func _apply_modifiers(modifiers: Array[StatModifier]):
	var state = _get_state()
	if not state:
		return
	for m in modifiers:
		_apply_one(state, m)


func _remove_modifiers(modifiers: Array[StatModifier]):
	var state = _get_state()
	if not state:
		return
	for m in modifiers:
		_remove_one(state, m)


func _apply_one(state: StateComponent, m: StatModifier):
	var key = _target_to_string(m.target_stat)
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses":
			var dict = state.defenses
			var old = dict.get(key, 0.0)
			dict[key] = _calc_modifier(old, m.value, m.modifier_type)
		"bonuses":
			var dict = state.bonuses
			var old = dict.get(key, 0.0)
			dict[key] = _calc_modifier(old, m.value, m.modifier_type)
		_:
			_set_stat_property(state, key, m)


func _remove_one(state: StateComponent, m: StatModifier):
	var key = _target_to_string(m.target_stat)
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses", "bonuses":
			var dict = state.defenses if prefix == "defenses" else state.bonuses
			var old = dict.get(key, 0.0)
			dict[key] = _unapply_modifier(old, m.value, m.modifier_type)
		_:
			_set_stat_property(state, key, null, m)


func _set_stat_property(state: StateComponent, key: String, m: StatModifier, inverse: StatModifier = null):
	match key:
		"max_hp":
			if inverse:
				state.max_hp = _unapply_modifier(state.max_hp, inverse.value, inverse.modifier_type)
			else:
				state.max_hp = _calc_modifier(state.max_hp, m.value, m.modifier_type)
		"hp_regen":
			if inverse:
				state.hp_regen = _unapply_modifier(state.hp_regen, inverse.value, inverse.modifier_type)
			else:
				state.hp_regen = _calc_modifier(state.hp_regen, m.value, m.modifier_type)
		"max_energy":
			if inverse:
				state.max_energy = _unapply_modifier(state.max_energy, inverse.value, inverse.modifier_type)
			else:
				state.max_energy = _calc_modifier(state.max_energy, m.value, m.modifier_type)
		"energy_regen":
			if inverse:
				state.energy_regen = _unapply_modifier(state.energy_regen, inverse.value, inverse.modifier_type)
			else:
				state.energy_regen = _calc_modifier(state.energy_regen, m.value, m.modifier_type)
		"max_stamina":
			if inverse:
				state.max_stamina = _unapply_modifier(state.max_stamina, inverse.value, inverse.modifier_type)
			else:
				state.max_stamina = _calc_modifier(state.max_stamina, m.value, m.modifier_type)
		"stamina_regen":
			if inverse:
				state.stamina_regen = _unapply_modifier(state.stamina_regen, inverse.value, inverse.modifier_type)
			else:
				state.stamina_regen = _calc_modifier(state.stamina_regen, m.value, m.modifier_type)
		"heat_cooling":
			if inverse:
				state.heat_cooling = _unapply_modifier(state.heat_cooling, inverse.value, inverse.modifier_type)
			else:
				state.heat_cooling = _calc_modifier(state.heat_cooling, m.value, m.modifier_type)


func _calc_modifier(base: float, value: float, type: EquipmentEnums.ModifierType) -> float:
	match type:
		EquipmentEnums.ModifierType.ADD:
			return base + value
		EquipmentEnums.ModifierType.MUL:
			return base * (1.0 + value)
		EquipmentEnums.ModifierType.OVERRIDE:
			return value
	return base


func _unapply_modifier(base: float, value: float, type: EquipmentEnums.ModifierType) -> float:
	match type:
		EquipmentEnums.ModifierType.ADD:
			return base - value
		EquipmentEnums.ModifierType.MUL:
			return base / (1.0 + value)
		EquipmentEnums.ModifierType.OVERRIDE:
			return EquipmentEnums.ModifierType.ADD  # cannot reverse override; return base unchanged
	return base


func _target_to_string(t: EquipmentEnums.StatTarget) -> String:
	match t:
		EquipmentEnums.StatTarget.MAX_HP: return "max_hp"
		EquipmentEnums.StatTarget.HP_REGEN: return "hp_regen"
		EquipmentEnums.StatTarget.MAX_ENERGY: return "max_energy"
		EquipmentEnums.StatTarget.ENERGY_REGEN: return "energy_regen"
		EquipmentEnums.StatTarget.MAX_STAMINA: return "max_stamina"
		EquipmentEnums.StatTarget.STAMINA_REGEN: return "stamina_regen"
		EquipmentEnums.StatTarget.MOVE_SPEED: return "move_speed"
		EquipmentEnums.StatTarget.ATTACK_SPEED: return "attack_speed"
		EquipmentEnums.StatTarget.ATTACK_DAMAGE: return "attack_damage"
		EquipmentEnums.StatTarget.CRIT_RATE: return "crit_rate"
		EquipmentEnums.StatTarget.CRIT_DAMAGE: return "crit_damage"
		EquipmentEnums.StatTarget.PUNCTURE_DEF: return "puncture_def"
		EquipmentEnums.StatTarget.SLASH_DEF: return "slash_def"
		EquipmentEnums.StatTarget.SMASH_DEF: return "smash_def"
		EquipmentEnums.StatTarget.FIRE_DEF: return "fire_def"
		EquipmentEnums.StatTarget.LIGHTNING_DEF: return "lightning_def"
		EquipmentEnums.StatTarget.ICE_DEF: return "ice_def"
		EquipmentEnums.StatTarget.POISON_DEF: return "poison_def"
		EquipmentEnums.StatTarget.WIND_DEF: return "wind_def"
		EquipmentEnums.StatTarget.PUNCTURE_BONUS: return "puncture_bonus"
		EquipmentEnums.StatTarget.SLASH_BONUS: return "slash_bonus"
		EquipmentEnums.StatTarget.SMASH_BONUS: return "smash_bonus"
		EquipmentEnums.StatTarget.FIRE_BONUS: return "fire_bonus"
		EquipmentEnums.StatTarget.LIGHTNING_BONUS: return "lightning_bonus"
		EquipmentEnums.StatTarget.ICE_BONUS: return "ice_bonus"
		EquipmentEnums.StatTarget.POISON_BONUS: return "poison_bonus"
		EquipmentEnums.StatTarget.WIND_BONUS: return "wind_bonus"
		EquipmentEnums.StatTarget.DODGE_COOLDOWN: return "dodge_cooldown"
		EquipmentEnums.StatTarget.DODGE_DISTANCE: return "dodge_distance"
		EquipmentEnums.StatTarget.HEAT_PER_ATTACK: return "heat_per_attack"
		EquipmentEnums.StatTarget.HEAT_COOLING: return "heat_cooling"
	return ""
