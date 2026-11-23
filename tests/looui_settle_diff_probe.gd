extends Node

# loot_ui 间歇问题诊断探针（只读，不改生产/测试逻辑）。
# 复现 "_snapshot 不变但已结算" 场景，反射扫描结算前后 duel 状态字段差异，
# 找出 _snapshot() 未覆盖的字段。隔离 APPDATA 运行。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _boot() -> void:
	var res: PackedScene = load(DUEL_SCENE)
	_duel = res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel._confirm_loadout()
	await _frames(3)

func _fresh() -> void:
	_duel.growth.reset_run()
	_duel.mastery.reset_run()
	_duel._post_battle.reset_run()
	_duel.player_hp_max = 100
	_duel.player_hp = 100
	_duel.turn_count = 1
	_duel.room_index = 0
	_duel.in_interroom = false
	_duel.hud.set_interroom_enabled(false)
	_duel.hud.hide_reward_screen()
	_duel.room_flow.reset_flow()

# 与测试 _snapshot 同口径
func _snapshot() -> String:
	var cir := ""
	if _duel.circuit_system != null:
		cir = str(_duel.circuit_system.equipped)
	return "%d|%d|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [
		_duel.gold, _duel.player_hp, str(_duel.selected_loadout), str(_duel.selected_charms),
		_duel.consumable_slots.size(),
		_duel._reward_system.run_power_bonus, _duel._reward_system.run_shield_next,
		str(_duel.mastery.imprints), str(_duel.growth.perk_ids), cir,
		str(_duel.reel_controls), str(_duel._reward_system.run_symbol_bonus),
		str(_duel.symbol_effect_overrides), str(_duel.pattern_param_overrides),
		str(_duel.element_affinity)]

# 反射扫描一批可能的状态字段（对象 -> 属性名 -> 值字符串）
func _wide_state() -> Dictionary:
	var d := {}
	var objects := {
		"duel": _duel,
		"growth": _duel.growth,
		"mastery": _duel.mastery,
		"reward": _duel._reward_system,
		"post": _duel._post_battle,
		"circuit": _duel.circuit_system,
		"consumable": _duel.consumable_system,
	}
	for obj_name in objects:
		var obj = objects[obj_name]
		if obj == null:
			continue
		for p in obj.get_property_list():
			var n := String(p.get("name", ""))
			if n.begins_with("_") and n.length() > 1 and n[1] == "_":
				continue
			var val = obj.get(n)
			if val is int or val is float or val is String or val is bool or val is Array or val is Dictionary:
				d[obj_name + "." + n] = str(val)
	return d

func _run() -> void:
	await _boot()
	var found := 0
	for attempt in range(40):
		_fresh()
		_duel.room_flow.begin_post_battle()
		await _frames(4)
		var opts: Array = _duel.room_flow.loot_view().get("options", [])
		var idx := -1
		for i in range(opts.size()):
			var o: Dictionary = opts[i]
			if not bool(o.get("needs_replace", false)) and String(o.get("kind", "")) != "queued_growth":
				idx = i
				break
		if idx < 0:
			continue
		var reward_id := String((opts[idx] as Dictionary).get("id", "?"))
		var before := _snapshot()
		var wide_before := _wide_state()
		_duel._on_loot_offer_chosen(idx)
		var after := _snapshot()
		if before == after:
			found += 1
			var wide_after := _wide_state()
			var diffs := []
			for k in wide_before.keys():
				if wide_before[k] != wide_after.get(k, "<missing>"):
					diffs.append("%s: %s -> %s" % [k, wide_before[k], wide_after.get(k, "<missing>")])
			print("DIFF|attempt=%d reward_id=%s idx=%d" % [attempt, reward_id, idx])
			for line in diffs:
				print("DIFF|  " + line)
			if found >= 6:
				break
	print("DIFF_PROBE|found=%d/40" % found)
