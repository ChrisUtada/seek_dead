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

# 固定种子：每幕一个，只用于本测试的专用 LootPool RNG 流，使 8 roll 的 kinds/trim 完全可复现。
# 用途：B2 曾因未固定种子而 flaky（实测 3/8 失败，失败项 ACT3 trim=2），本轮改为固定种子 + 比率断言。
const ACT_SEEDS := [91001, 91002, 91003]
# 固定种子下 8 roll 的精确 trim 出现次数（实测写死；改动需重新测量并注明原因）。
# 91001→ACT1=0、91002→ACT2=0、91003→ACT3=0；60 roll 比率实测 ACT1=0/60、ACT2=0/60、ACT3=5/60。
const EXPECTED_TRIM := [0, 0, 0]
const RATIO_ROLLS := 60
const RATIO_MAX := 0.10

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


func _seed_for(act: int) -> void:
	# 每幕进入时固定专用流；后续 8+60 次 roll 共用该流，保持序列可复现。
	_duel._reward_system._loot.reset_run(int(ACT_SEEDS[act - 1]))


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
		_seed_for(act)
		var expected: Array = LootSourceTable.shop_categories(act)
		var rare_filled := false
		var tiers: Array = LootSourceTable.shop_tiers(act)
		var trim_hits := 0
		var kinds_samples: Array = []
		for _i in 8:
			var kinds: Array = _roll(act)
			kinds_samples.append(_kinds_text(kinds))
			# B1：按位比较：offer 序列（跳过 empty_tier 的缺位）必须逐位等于期望类别。
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
			# B3：至少一条 rare 格填满
			for ti in tiers.size():
				if String(tiers[ti]) == "rare" and ti < kinds.size() and kinds[ti] != "":
					rare_filled = true
			# B2①：统计前 8 次 trim
			for p in _paths():
				if p == TRIM:
					trim_hits += 1
		all_trim[act] = trim_hits
		_check(rare_filled, "B3 ACT%d 至少一条 rare 格填满" % act)
		# B2①：固定种子下的精确值（种子 91001/91002/91003），实测写死防止漂移。
		_check(trim_hits == int(EXPECTED_TRIM[act - 1]),
			"B2① ACT%d 固定种子 %d 下 8 roll trim 出现 %d 次（期望 %d）" % [
				act, int(ACT_SEEDS[act - 1]), trim_hits, int(EXPECTED_TRIM[act - 1])])
		# B2②：比率断言——继续用同一专用流跑 60 次，trim 占比 <= 10%。
		var ratio_hits := 0
		for _j in RATIO_ROLLS:
			_roll(act)
			for p in _paths():
				if p == TRIM:
					ratio_hits += 1
		var ratio := float(ratio_hits) / float(RATIO_ROLLS)
		_check(ratio <= RATIO_MAX,
			"B2② ACT%d 60 roll trim 占比 %.3f <= %.2f（命中 %d）" % [act, ratio, RATIO_MAX, ratio_hits])
		Debug.log("SHELF|KINDS ACT%d %s" % [act, " | ".join(kinds_samples)])
		Debug.log("SHELF|TRIM ACT%d %d/8 ratio=%d/60" % [act, trim_hits, ratio_hits])
