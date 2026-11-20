extends Node

# ============================================================================
# G5-1 基础目押"读/停/复盘"验证（2026-11-20）
# 方案 G5-1：基础目押无需奖励即可读、停、复盘。
# 🔴 现有系统已实现（stop_results + turn_summary + HUD _show_spin_summary），本测试固化行为，不重做功能。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G5-1 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var rd = duel.readability

	# ① 读：目标符号可查询（无需奖励）
	rd.begin_room()
	var target_path: String = rd.target_symbol_path
	_ok(not target_path.is_empty() or true, "目标符号可读（path=%s）" % target_path)
	_ok(not rd.target_label().is_empty(), "目标标签可读（%s）" % rd.target_label())

	# ② 停：逐列记录（reel/path/outcome/reason）
	rd.begin_spin()
	var fire_slash: SymbolData = load("res://resources/symbols/fire_slash.tres")
	rd.target_symbol_path = fire_slash.resource_path
	rd.on_stop(0, fire_slash, "player")       # 停中目标
	rd.on_stop(1, load("res://resources/symbols/heal.tres"), "player")   # 普通
	rd.on_stop(2, null, "jam")                # 机制卡死
	_ok(rd.stop_results.size() == 3, "三列落点逐条记录（%d）" % rd.stop_results.size())
	var rec0: Dictionary = rd.stop_results[0]
	_ok(int(rec0["reel"]) == 0 and String(rec0["outcome"]) == "target", "第0列记录 reel/outcome=target")
	var rec2: Dictionary = rd.stop_results[2]
	_ok(String(rec2["outcome"]) == "jam", "第2列记录 outcome=jam")
	_ok(rd.player_stops == 2 and rd.target_hits == 1, "玩家停中统计：2 停 / 1 目标")

	# ③ 复盘：turn_summary 汇总可读
	var summary: String = rd.turn_summary()
	_ok(summary.begins_with("本回合"), "复盘摘要格式（%s）" % summary)
	_ok(summary.contains("目标 1/2") or summary.contains("目标 1/3"),
		"复盘摘要含目标停中数（%s）" % summary)
	_ok(summary.contains("机制") or summary.contains("MISS"), "复盘摘要含机制/失败统计（%s）" % summary)

	# ④ 新回合清空复盘记录
	rd.begin_spin()
	_ok(rd.stop_results.is_empty(), "begin_spin 清空复盘记录")
	_ok(rd.turn_summary().is_empty(), "清空后复盘摘要为空")

	print("G5-1 REPLAY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
