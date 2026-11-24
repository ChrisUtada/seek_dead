extends Node

# ============================================================================
# 商店货架类别契约（2026-11-24）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/shop_shelf_contract_test.tscn
# 背景：ACT1 第 4 格 rare/passive 空池回退到 rare active，唯一候选 trim_scissors → 每店必出。
# 验收：B1 三幕 ×8 roll 的 kind 序列 == LootSourceTable.shop_categories(act)（允许 empty_tier 留空）；
#       B2 同幕连续 3 次 roll，trim_scissors 出现次数 <= 1；
#       B3 三幕各至少一条 rare 格能填满。
# ============================================================================

const TRIM := "res://resources/consumables/trim_scissors.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	await _run()
	print("SHELF|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _roll(act: int) -> Array:
	_duel.current_act = act
	_duel.room_index = 0
	_duel._shop_system.reset_run()
	_duel._shop_system.roll_shop()
	var kinds: Array[String] = []
	for o in _duel._shop_system.shop_offers:
		kinds.append(String(o.get("kind", "")))
	return kinds


func _paths() -> Array[String]:
	var out: Array[String] = []
	for o in _duel._shop_system.shop_offers:
		out.append(String(o.get("path", "")))
	return out


func _kinds_text(kinds: Array) -> String:
	return "[%s]" % ", ".join(kinds)


func _run() -> void:
	var all_trim := {}
	for act in [1, 2, 3]:
		var expected: Array = LootSourceTable.shop_categories(act)
		var rare_filled := false
		var tiers: Array = LootSourceTable.shop_tiers(act)
		var trim_hits := 0
		var kinds_samples: Array = []
		for _i in 8:
			var kinds: Array = _roll(act)
			kinds_samples.append(_kinds_text(kinds))
			# B1：按位比较：offer 序列（跳过 empty_tier 的缺位）必须逐位等于期望类别。
			# 当前 bug：ACT1 第 4 格 passive 位实际出 active → 断言红。
			var mismatch := ""
			for ci in range(mini(kinds.size(), expected.size())):
				if kinds[ci] != String(expected[ci]):
					mismatch = "slot%d 实际=%s 期望=%s" % [ci, kinds[ci], String(expected[ci])]
					break
			if kinds.size() > expected.size():
				mismatch = "offer 数 %d > 类别数 %d" % [kinds.size(), expected.size()]
			_check(mismatch == "", "B1 ACT%d 第 %d 次 roll kind 序列合法（%s，期望 %s）%s" % [
				act, _i + 1, _kinds_text(kinds), str(expected), mismatch])
			# B4：三幕 8 roll 空槽数 == 0（roll_shop 跳过 ok:false 槽会让 offers 变短）
			_check(_duel._shop_system.shop_offers.size() == 4,
				"B4 ACT%d 第 %d 次 roll 空槽数 0（实测 %d 格）" % [act, _i + 1, _duel._shop_system.shop_offers.size()])
			# B3：至少一条 rare 格填满（按 tiers 中的 rare 下标检查对应 offer 存在且 kind 非空）
			for ti in tiers.size():
				if String(tiers[ti]) == "rare" and ti < kinds.size() and kinds[ti] != "":
					rare_filled = true
			# B2：统计 trim
			for p in _paths():
				if p == TRIM:
					trim_hits += 1
			if _i == 2:
				# 同幕连续 3 次 roll 的 trim 总数（累计前 3 次）
				pass
		all_trim[act] = trim_hits
		_check(rare_filled, "B3 ACT%d 至少一条 rare 格填满" % act)
		_check(trim_hits <= 1, "B2 ACT%d 8 次 roll 中 trim_scissors 出现 %d 次（<=1）" % [act, trim_hits])
		# 真实 kinds 统计打印一份，供回报引用
		Debug.log("SHELF|KINDS ACT%d %s" % [act, " | ".join(kinds_samples)])
		Debug.log("SHELF|TRIM ACT%d %d/8" % [act, trim_hits])
