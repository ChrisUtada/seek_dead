extends Node

# ============================================================================
# P1-A 类别多样性测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p1_category_diversity_test.tscn
#
# 覆盖：修复"7类设计只剩2类在跑"的结构性失衡
# ① 连续生成 200 组 Draft（600 卡），当前有候选的 3 类全部覆盖
#    （rule_mod/reel_control 零候选属 P1-B/C 范围，补齐后应≥4类）
# ② survival_resource（此前 0 次出现）不再为 0
# ③ 单一类别不超过总量的 60%（此前 symbol_mod 66.7%）
# ④ 同一组内同类不超过 MAX_SAME_CATEGORY
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P1-A FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _run() -> void:
	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	var rs = duel._reward_system
	var snap = RunStateAnalyzer.capture(duel)

	var appeared := {}
	var total := 0
	var group_violations := 0
	for i in range(200):
		var d = rs._draft_composer.compose(snap, 3, false, rs._draft_extra(), false)
		var cat_count := {}
		for r in (d.rewards as Array):
			var c: String = r.effective_category()
			appeared[c] = int(appeared.get(c, 0)) + 1
			cat_count[c] = int(cat_count.get(c, 0)) + 1
			total += 1
		for c in cat_count:
			if int(cat_count[c]) > 2:
				group_violations += 1

	_ok(appeared.size() >= 3, "at least 3 categories appear (got %d: %s)" % [
		appeared.size(), str(appeared)])
	_ok(int(appeared.get("survival_resource", 0)) > 0, "survival_resource appears (got %d)" % int(appeared.get("survival_resource", 0)))
	var max_count := 0
	for c in appeared:
		max_count = maxi(max_count, int(appeared[c]))
	_ok(float(max_count) / float(total) <= 0.60, "no category >60%% (max=%d/%d=%.1f%%)" % [
		max_count, total, 100.0 * float(max_count) / float(total)])
	_ok(group_violations == 0, "no group with >2 same category (violations=%d)" % group_violations)

	print("P1DIVERSITY RESULT: %d checks, %d fails; dist=%s" % [_checks, _fails, str(appeared)])
	get_tree().quit(1 if _fails > 0 else 0)
