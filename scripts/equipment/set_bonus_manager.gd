class_name SetBonusManager
extends Node

signal set_pieces_changed(set_id: String, count: int)
signal set_bonus_activated(set_id: String, tier: int)

var _active_sets: Dictionary = {}  # set_id → piece_count


func _get_state() -> StateComponent:
	var p = get_parent()
	if not p:
		return null
	return p.get_node_or_null("StateComponent") as StateComponent


func _get_equipped() -> Dictionary:
	var p = get_parent()
	if not p or not p.has_method("get_all_equipped"):
		return {}
	return p.get_all_equipped()


func check_all():
	var counts: Dictionary = {}
	var equipped = _get_equipped()
	for slot_idx in equipped:
		var item = equipped[slot_idx] as EquipmentBase
		if not item or item.set_id.is_empty():
			continue
		counts[item.set_id] = counts.get(item.set_id, 0) + 1
	_apply_changes(counts)


func _apply_changes(new_counts: Dictionary):
	var all_ids = []
	for id in _active_sets.keys():
		all_ids.append(id)
	for id in new_counts.keys():
		if id not in all_ids:
			all_ids.append(id)
	for id in all_ids:
		var old_count = _active_sets.get(id, 0)
		var new_count = new_counts.get(id, 0)
		if old_count == new_count:
			continue
		_active_sets[id] = new_count
		if new_count >= 3:
			_activate_tier(id, 3)
		elif new_count >= 2:
			_activate_tier(id, 2)
		else:
			_deactivate(id)
		set_pieces_changed.emit(id, new_count)


func _activate_tier(set_id: String, tier: int):
	var set_def = SetDatabase.get_set(set_id)
	if not set_def:
		return
	var state = _get_state()
	if not state:
		return
	if tier >= 2:
		for m in set_def.bonus_2pc_modifiers:
			var key = SetDatabase.target_key(m.target_stat)
			SetDatabase.apply_to_state(state, key, m)
	if tier >= 3:
		for m in set_def.bonus_3pc_modifiers:
			var key = SetDatabase.target_key(m.target_stat)
			SetDatabase.apply_to_state(state, key, m)
		var p = get_parent()
		if p and p.has_method("register_set_trigger"):
			for e in set_def.bonus_3pc_triggers:
				p.register_set_trigger(e)
	set_bonus_activated.emit(set_id, tier)
	print("[套装] %s %d件激活" % [set_def.set_name, tier])


func _deactivate(set_id: String):
	var set_def = SetDatabase.get_set(set_id)
	if not set_def:
		return
	var old_tier = _active_sets.get(set_id, 0)
	_active_sets[set_id] = 0
	var state = _get_state()
	if not state:
		return
	if old_tier >= 2:
		for m in set_def.bonus_2pc_modifiers:
			var key = SetDatabase.target_key(m.target_stat)
			SetDatabase.unapply_to_state(state, key, m)
	if old_tier >= 3:
		for m in set_def.bonus_3pc_modifiers:
			var key = SetDatabase.target_key(m.target_stat)
			SetDatabase.unapply_to_state(state, key, m)
		var p = get_parent()
		if p and p.has_method("unregister_set_trigger"):
			for e in set_def.bonus_3pc_triggers:
				p.unregister_set_trigger(e)
	print("[套装] %s 已停用" % [set_def.set_name])
