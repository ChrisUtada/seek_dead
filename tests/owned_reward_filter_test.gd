extends Node

# ============================================================================
# 已拥有奖励过滤测试（2026-11-19）
# 用户反馈："已经选过的应该不要再出现"。
# 根因：Resolver 有 already_owned 检查（选中时），但生成期 _eligible 不检查，
#       导致已拥有的操控/技艺卡仍进入三选一候选。
# 修复：RewardSystem._owned_reward_ids() → composer.set_owned_ids() → _eligible 过滤。
#
# 覆盖：
# ① 已拥有的操控卡（reel_controls）不出现在候选
# ② 已拥有的技艺（perk_ids）不出现在候选
# ③ 未拥有的仍能正常出现
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("OWNED FILTER FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame

	var rs = duel._reward_system

	# ① 已拥有操控卡不出现：给全部 3 个操控，生成后候选里不应有 control_*
	duel.reel_controls["trash_reroll"] = true
	duel.reel_controls["slow_ramp"] = true
	duel.reel_controls["mercy"] = true
	var owned: Array = rs._owned_reward_ids()
	_ok(owned.has("control_trash_reroll") and owned.has("control_slow_ramp") and owned.has("control_mercy"),
		"owned ids include all controls")

	# 用 composer 验证过滤（直接调 compose，设置 owned_ids）
	var snap = RunStateAnalyzer.capture(duel)
	rs._draft_composer.set_owned_ids(owned)
	var has_control := false
	for i in range(200):
		var d = rs._draft_composer.compose(snap, 3, false, [], false)
		for r in (d.rewards as Array):
			if String(r.id).begins_with("control_"):
				has_control = true
				break
		if has_control:
			break
	_ok(not has_control, "owned controls never appear in 200 drafts")

	# ② 已拥有技艺不出现
	if duel.growth != null:
		duel.growth.perk_ids.append("tough")
		var owned2: Array = rs._owned_reward_ids()
		_ok(owned2.has("perk_tough"), "owned ids include perk_tough")
		rs._draft_composer.set_owned_ids(owned2)
		var has_tough := false
		for i in range(200):
			var d2 = rs._draft_composer.compose(snap, 3, false, [], false)
			for r in (d2.rewards as Array):
				if String(r.id) == "perk_tough":
					has_tough = true
					break
			if has_tough:
				break
		_ok(not has_tough, "owned perk never appears in 200 drafts")

	# ③ 未拥有操控清空后能出现
	duel.reel_controls.clear()
	rs._draft_composer.set_owned_ids(rs._owned_reward_ids())
	var ctrl_appeared := false
	for i in range(200):
		var d3 = rs._draft_composer.compose(snap, 3, false, [], false)
		for r in (d3.rewards as Array):
			if String(r.id).begins_with("control_"):
				ctrl_appeared = true
				break
		if ctrl_appeared:
			break
	_ok(ctrl_appeared, "unowned controls can appear")

	print("OWNED FILTER RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
