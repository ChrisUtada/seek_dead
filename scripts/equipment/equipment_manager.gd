class_name EquipmentManager
extends Node

signal equipment_equipped(slot: int, item: EquipmentBase)
signal equipment_unequipped(slot: int)
signal trigger_activated(event: int, effect: TriggerEffect)

var _equipped: Dictionary = {}
var _active_triggers: Array[Dictionary] = []
var _active_conditions: Array[Dictionary] = []

var _executor: EffectExecutor
var _set_manager: SetBonusManager
var _in_trigger: bool = false


func _ready():
	_executor = EffectExecutor.new()
	_executor.name = "EffectExecutor"
	add_child(_executor)
	_set_manager = SetBonusManager.new()
	_set_manager.name = "SetBonusManager"
	add_child(_set_manager)
	trigger_activated.connect(_on_trigger_activated)
	EventManager.damage_dealt.connect(_on_damage_dealt)
	EventManager.enemy_died.connect(_on_enemy_died)
	EventManager.room_cleared.connect(_on_room_cleared)
	EventManager.skill_used.connect(_on_skill_used)
	EventManager.item_picked_up.connect(_on_item_picked_up)
	EventManager.dodge_performed.connect(_on_dodge_performed)
	var state = _get_state()
	if state:
		state.meltdown_triggered.connect(_on_meltdown_local)
		state.stamina_depleted.connect(_on_stamina_depleted)
	Debug.log("[EquipmentManager] 就绪")


func _on_trigger_activated(event: int, effect: TriggerEffect):
	var scaled = effect.duplicate() as TriggerEffect
	scaled.param_value = _scale_param(effect)
	_executor.execute(scaled, {})


func _on_damage_dealt(attacker: Node2D, defender: Node2D, amount: float, damage_type: int):
	if not defender:
		return
	var p = _get_player()
	if not p:
		return
	if defender == p:
		on_trigger_event(EquipmentEnums.TriggerEvent.ON_HURT)
	elif defender.is_in_group("enemies"):
		on_trigger_event(EquipmentEnums.TriggerEvent.ON_HIT)


func _on_enemy_died(enemy: Node2D):
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_KILL)


func _on_room_cleared(room_id: String):
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_ROOM_CLEAR)


func _on_skill_used(skill_data: Dictionary):
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_SKILL_USE)


func _on_item_picked_up(item_data: Dictionary):
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_PICKUP)


func _on_dodge_performed():
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_DODGE)


func _on_meltdown_local():
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_MELTDOWN)


func _on_stamina_depleted():
	on_trigger_event(EquipmentEnums.TriggerEvent.ON_STATUS_INFLICT)


func _scale_param(effect: TriggerEffect) -> float:
	var val = effect.param_value
	match effect.effect_action:
		EquipmentEnums.EffectAction.EXPLODE, EquipmentEnums.EffectAction.KNOCKBACK:
			val = RoomContext.scale_radius(val)
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING:
			val = RoomContext.scale_chain_count(int(val))
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE:
			val = RoomContext.scale_projectile_count(int(val))
	return val


func _scale_chance(base: float) -> float:
	return RoomContext.scale_chance(base, 0)


func _get_player() -> Node2D:
	var p = get_parent()
	if not p:
		return null
	return p as Node2D


func equip(item: EquipmentBase):
	var slot = item.slot

	# 副手校验：非可双持武器不能装副手
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND and item.weapon_data and not item.weapon_data.can_dual_wield:
		return

	unequip(slot)
	_equipped[slot] = item
	_apply_item(item)

	# 武器槽特殊处理：将 WeaponData 注入 WeaponComponent
	if (slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN or slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND) and item.weapon_data:
		var player = get_parent()
		var wc = player.get_node_or_null("WeaponComponent") as WeaponComponent
		if wc:
			wc.equip_weapon(item, slot)

	EventManager.equipment_changed.emit(slot, item)
	equipment_equipped.emit(slot, item)
	if _set_manager:
		_set_manager.check_all()


func unequip(slot: int):
	var old = _equipped.get(slot) as EquipmentBase
	if not old:
		return

	# 武器槽卸下处理
	if slot == EquipmentEnums.EquipmentSlot.WEAPON_MAIN or slot == EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND:
		var player = get_parent()
		var wc = player.get_node_or_null("WeaponComponent") as WeaponComponent
		if wc:
			wc.unequip_weapon(slot)

	_remove_item(old)
	_equipped.erase(slot)
	EventManager.equipment_changed.emit(slot, null)
	equipment_unequipped.emit(slot)
	if _set_manager:
		_set_manager.check_all()


func register_set_trigger(e: TriggerEffect):
	_register_trigger(e)


func unregister_set_trigger(e: TriggerEffect):
	_unregister_trigger(e)


func get_equipped(slot: int) -> EquipmentBase:
	return _equipped.get(slot) as EquipmentBase


func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


func _get_state() -> StateComponent:
	var p = get_parent()
	if not p:
		return null
	return p.get_node_or_null("StateComponent") as StateComponent


func _apply_item(item: EquipmentBase):
	for affix in item.affixes:
		for m in affix.stat_modifiers:
			var state = _get_state()
			if state:
				_apply_modifier(state, m)
		for e in affix.trigger_effects:
			_register_trigger(e)
		for c in affix.conditional_bonuses:
			_register_condition(c)


func _remove_item(item: EquipmentBase):
	for affix in item.affixes:
		for m in affix.stat_modifiers:
			var state = _get_state()
			if state:
				_remove_modifier(state, m)
		for e in affix.trigger_effects:
			_unregister_trigger(e)
		for c in affix.conditional_bonuses:
			_unregister_condition(c)


func _apply_modifier(state: StateComponent, m: StatModifier):
	var key = _target_to_string(m.target_stat)
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses":
			var dict = state.defenses
			dict[key] = _calc_modifier(dict.get(key, 0.0), m.value, m.modifier_type)
		"bonuses":
			var dict = state.bonuses
			dict[key] = _calc_modifier(dict.get(key, 0.0), m.value, m.modifier_type)
		_:
			_set_stat_property(state, key, m)


func _remove_modifier(state: StateComponent, m: StatModifier):
	var key = _target_to_string(m.target_stat)
	var prefix = ""
	if key.ends_with("_def"):
		prefix = "defenses"
	elif key.ends_with("_bonus"):
		prefix = "bonuses"
	match prefix:
		"defenses", "bonuses":
			var dict = state.defenses if prefix == "defenses" else state.bonuses
			dict[key] = _unapply_modifier(dict.get(key, 0.0), m.value, m.modifier_type)
		_:
			_set_stat_property(state, key, null, m)


func _set_stat_property(state: StateComponent, key: String, m: StatModifier, inverse: StatModifier = null):
	var mod = inverse if inverse else m
	var apply = inverse == null
	match key:
		"max_hp":
			state.max_hp = _calc_modifier(state.max_hp, mod.value, mod.modifier_type) if apply else _unapply_modifier(state.max_hp, mod.value, mod.modifier_type)
			if mod.modifier_type == EquipmentEnums.ModifierType.ADD:
				state.hp += mod.value if apply else -mod.value
		"hp_regen", "max_energy", "energy_regen", "max_stamina", "stamina_regen", "heat_cooling":
			var current = state.get(key)
			state.set(key, _calc_modifier(current, mod.value, mod.modifier_type) if apply else _unapply_modifier(current, mod.value, mod.modifier_type))


func _calc_modifier(base: float, value: float, type: EquipmentEnums.ModifierType) -> float:
	match type:
		EquipmentEnums.ModifierType.ADD: return base + value
		EquipmentEnums.ModifierType.MUL: return base * (1.0 + value)
		EquipmentEnums.ModifierType.OVERRIDE: return value
	return base


func _unapply_modifier(base: float, value: float, type: EquipmentEnums.ModifierType) -> float:
	match type:
		EquipmentEnums.ModifierType.ADD: return base - value
		EquipmentEnums.ModifierType.MUL: return base / (1.0 + value)
		EquipmentEnums.ModifierType.OVERRIDE:
			return base
	return base


func _register_trigger(e: TriggerEffect):
	_active_triggers.append({ "effect": e, "last_trigger": 0.0 })


func _unregister_trigger(e: TriggerEffect):
	for i in range(_active_triggers.size() - 1, -1, -1):
		if _active_triggers[i].get("effect") == e:
			_active_triggers.remove_at(i)
			return


func _register_condition(c: ConditionalBonus):
	_active_conditions.append({ "bonus": c, "currently_active": false })


func _unregister_condition(c: ConditionalBonus):
	for i in range(_active_conditions.size() - 1, -1, -1):
		if _active_conditions[i].get("bonus") == c:
			_active_conditions.remove_at(i)
			return


func on_trigger_event(event: int):
	if _in_trigger:
		return
	_in_trigger = true
	var now = Time.get_ticks_msec() / 1000.0
	for entry in _active_triggers:
		var e = entry.effect as TriggerEffect
		if e.trigger_event != event:
			continue
		if now - entry.last_trigger < e.cooldown:
			continue
		var effective_chance = _scale_chance(e.chance)
		if randf() > effective_chance:
			continue
		entry.last_trigger = now
		trigger_activated.emit(event, e)
	_in_trigger = false


func _process(delta: float):
	var state = _get_state()
	if not state:
		return
	for entry in _active_conditions:
		var c = entry.bonus as ConditionalBonus
		var active = _evaluate_condition(c, state)
		if active != entry.currently_active:
			entry.currently_active = active
			if active:
				_apply_modifier(state, c.bonus)
			else:
				_remove_modifier(state, c.bonus)


func _evaluate_condition(c: ConditionalBonus, state: StateComponent) -> bool:
	match c.condition:
		EquipmentEnums.ConditionType.HP_ABOVE:
			return state.get_normalized_hp() >= c.condition_value
		EquipmentEnums.ConditionType.HP_BELOW:
			return state.get_normalized_hp() <= c.condition_value
		EquipmentEnums.ConditionType.STAMINA_FULL:
			return state.stamina >= state.max_stamina
		EquipmentEnums.ConditionType.HEAT_ABOVE:
			return state.get_normalized_heat() >= c.condition_value
		EquipmentEnums.ConditionType.NO_AMMO:
			var p = get_parent()
			if p and p.has_node("AmmoSystem"):
				return p.get_node("AmmoSystem").current_ammo <= 0
			return false
		_:
			return false


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
