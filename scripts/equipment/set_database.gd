class_name SetDatabase
extends RefCounted


static func get_all_sets() -> Array[SetBonus]:
	return [
		_courier_set(),
		_flame_set(),
		_frost_set(),
		_venom_set(),
		_thunder_set(),
		_mystery_set(),
	]


static func get_set(id: String) -> SetBonus:
	for s in get_all_sets():
		if s.set_id == id:
			return s
	return null


static func _sm(target: int, type: int, val: float) -> StatModifier:
	var m = StatModifier.new()
	m.target_stat = target
	m.modifier_type = type
	m.value = val
	return m


static func _te(event: int, action: int, chance: float, val: float, cd: float = 0.0) -> TriggerEffect:
	var e = TriggerEffect.new()
	e.trigger_event = event
	e.effect_action = action
	e.chance = chance
	e.param_value = val
	e.cooldown = cd
	return e


static func target_key(t: int) -> String:
	match t:
		EquipmentEnums.StatTarget.MOVE_SPEED: return "move_speed"
		EquipmentEnums.StatTarget.DODGE_COOLDOWN: return "dodge_cooldown"
		EquipmentEnums.StatTarget.MAX_HP: return "max_hp"
		EquipmentEnums.StatTarget.HP_REGEN: return "hp_regen"
		EquipmentEnums.StatTarget.ENERGY_REGEN: return "energy_regen"
		EquipmentEnums.StatTarget.STAMINA_REGEN: return "stamina_regen"
		EquipmentEnums.StatTarget.CRIT_RATE: return "crit_rate"
		EquipmentEnums.StatTarget.CRIT_DAMAGE: return "crit_damage"
		EquipmentEnums.StatTarget.ATTACK_DAMAGE: return "attack_damage"
		EquipmentEnums.StatTarget.ATTACK_SPEED: return "attack_speed"
	return ""


static func apply_to_state(state: StateComponent, key: String, m: StatModifier):
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses":
			state.defenses[key] = state.defenses.get(key, 0.0) + m.value
		"bonuses":
			state.bonuses[key] = state.bonuses.get(key, 0.0) + m.value
		_:
			match key:
				"max_hp":
					state.max_hp += m.value
					if m.modifier_type == EquipmentEnums.ModifierType.ADD:
						state.hp += m.value
				"hp_regen", "max_energy", "energy_regen", "max_stamina", "stamina_regen", "heat_cooling":
					var current = state.get(key)
					state.set(key, current + m.value)
				_:
					var current = state.get(key)
					state.set(key, (current if current != null else 0.0) + m.value)


static func unapply_to_state(state: StateComponent, key: String, m: StatModifier):
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses":
			state.defenses[key] = state.defenses.get(key, 0.0) - m.value
		"bonuses":
			state.bonuses[key] = state.bonuses.get(key, 0.0) - m.value
		_:
			match key:
				"max_hp":
					state.max_hp -= m.value
					if m.modifier_type == EquipmentEnums.ModifierType.ADD:
						state.hp = max(state.hp - m.value, 0.0)
				"hp_regen", "max_energy", "energy_regen", "max_stamina", "stamina_regen", "heat_cooling":
					var current = state.get(key)
					state.set(key, current - m.value)
				_:
					var current = state.get(key)
					state.set(key, (current if current != null else 0.0) - m.value)


static func _courier_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "courier"
	s.set_name = "腐化外卖员"
	s.slots = [EquipmentEnums.EquipmentSlot.LEG, EquipmentEnums.EquipmentSlot.ACCESSORY_1, EquipmentEnums.EquipmentSlot.ACCESSORY_2]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.MOVE_SPEED, EquipmentEnums.ModifierType.MUL, 0.20),
		_sm(EquipmentEnums.StatTarget.DODGE_COOLDOWN, EquipmentEnums.ModifierType.ADD, -0.3),
	]
	s.bonus_3pc_triggers = [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.HEAL, 0.25, 0.0),
	]
	return s


static func _flame_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "flame"
	s.set_name = "烈焰配送"
	s.slots = [EquipmentEnums.EquipmentSlot.BODY, EquipmentEnums.EquipmentSlot.HAND, EquipmentEnums.EquipmentSlot.ACCESSORY_1]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.FIRE_BONUS, EquipmentEnums.ModifierType.ADD, 0.40),
	]
	s.bonus_3pc_triggers = [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.SPAWN_POOL, 1.0, 80.0),
	]
	return s


static func _frost_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "frost"
	s.set_name = "冰封仓库"
	s.slots = [EquipmentEnums.EquipmentSlot.BODY, EquipmentEnums.EquipmentSlot.LEG, EquipmentEnums.EquipmentSlot.ACCESSORY_2]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.ICE_BONUS, EquipmentEnums.ModifierType.ADD, 0.40),
	]
	s.bonus_3pc_triggers = [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.EXPLODE, 1.0, 100.0),
	]
	return s


static func _venom_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "venom"
	s.set_name = "毒物实验室"
	s.slots = [EquipmentEnums.EquipmentSlot.HAND, EquipmentEnums.EquipmentSlot.LEG, EquipmentEnums.EquipmentSlot.ACCESSORY_1]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.POISON_BONUS, EquipmentEnums.ModifierType.ADD, 0.50),
	]
	s.bonus_3pc_triggers = [
		_te(EquipmentEnums.TriggerEvent.ON_KILL, EquipmentEnums.EffectAction.SPAWN_POOL, 1.0, 80.0),
	]
	return s


static func _thunder_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "thunder"
	s.set_name = "高压电柜"
	s.slots = [EquipmentEnums.EquipmentSlot.BODY, EquipmentEnums.EquipmentSlot.HAND, EquipmentEnums.EquipmentSlot.ACCESSORY_2]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.LIGHTNING_BONUS, EquipmentEnums.ModifierType.ADD, 0.40),
		_sm(EquipmentEnums.StatTarget.CRIT_RATE, EquipmentEnums.ModifierType.ADD, 0.10),
	]
	s.bonus_3pc_triggers = [
		_te(EquipmentEnums.TriggerEvent.ON_CRIT, EquipmentEnums.EffectAction.CHAIN_LIGHTNING, 1.0, 5.0, 0.5),
	]
	return s


static func _mystery_set() -> SetBonus:
	var s = SetBonus.new()
	s.set_id = "mystery"
	s.set_name = "神秘外卖"
	s.slots = [EquipmentEnums.EquipmentSlot.HELMET, EquipmentEnums.EquipmentSlot.BODY, EquipmentEnums.EquipmentSlot.ACCESSORY_2]
	s.bonus_2pc_modifiers = [
		_sm(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.20),
		_sm(EquipmentEnums.StatTarget.HP_REGEN, EquipmentEnums.ModifierType.ADD, 3.0),
		_sm(EquipmentEnums.StatTarget.ENERGY_REGEN, EquipmentEnums.ModifierType.ADD, 2.0),
		_sm(EquipmentEnums.StatTarget.STAMINA_REGEN, EquipmentEnums.ModifierType.ADD, 4.0),
	]
	return s
