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

	# ============ S3-1b：回路拥有状态进入生成侧过滤 ============
	# 清空此前操控/技艺状态，聚焦回路
	duel.reel_controls.clear()
	if duel.growth != null: duel.growth.perk_ids.clear()
	duel.circuit_system.reset_run()

	# ④ 未拥有回路可生成：空仓库时 200 drafts 应出现 circuit_*
	rs._draft_composer.set_owned_ids(rs._owned_reward_ids())
	var circuit_appeared := false
	for i in range(200):
		var d4 = rs._draft_composer.compose(snap, 3, false, [], false)
		for r in (d4.rewards as Array):
			if String(r.id).begins_with("circuit_"):
				circuit_appeared = true
				break
		if circuit_appeared: break
	_ok(circuit_appeared, "unowned circuits can appear")

	# ⑤ 已拥有但未装备回路不再出现
	duel.circuit_system.acquire("circuit_pair")
	var owned_circuit: Array = rs._owned_reward_ids()
	_ok(owned_circuit.has("circuit_pair"), "owned ids include owned-but-unequipped circuit")
	rs._draft_composer.set_owned_ids(owned_circuit)
	var pair_appeared := false
	for i in range(200):
		var d5 = rs._draft_composer.compose(snap, 3, false, [], false)
		for r in (d5.rewards as Array):
			if String(r.id) == "circuit_pair":
				pair_appeared = true
				break
		if pair_appeared: break
	_ok(not pair_appeared, "owned-but-unequipped circuit never appears in 200 drafts")

	# ⑥ 已装备回路不再出现
	duel.circuit_system.equip("circuit_pair")
	_ok(duel.circuit_system.equipped.has("circuit_pair"), "circuit equipped for test")
	rs._draft_composer.set_owned_ids(rs._owned_reward_ids())
	var equipped_appeared := false
	for i in range(200):
		var d6 = rs._draft_composer.compose(snap, 3, false, [], false)
		for r in (d6.rewards as Array):
			if String(r.id) == "circuit_pair": equipped_appeared = true; break
		if equipped_appeared: break
	_ok(not equipped_appeared, "equipped circuit never appears in 200 drafts")

	# ⑦ 重抽与 Fallback 不绕过滤：compose_reroll 复用相同 owned_ids
	var prev_ids: Array = []
	for r in (rs._draft_composer.compose(snap, 3, false, [], false).rewards as Array):
		prev_ids.append(String(r.id))
	var reroll_bypass := false
	for i in range(30):
		var dr = rs._draft_composer.compose_reroll(snap, prev_ids, 3, false, [], false)
		for r in (dr.rewards as Array):
			if String(r.id) == "circuit_pair": reroll_bypass = true; break
		if reroll_bypass: break
	_ok(not reroll_bypass, "reroll does not bypass circuit ownership filter")

	# ⑧ 合法池缩小时不静默减少候选、不造无效卡：每次 compose 仍恰好 count 张
	var count_ok := true
	for i in range(60):
		var d8 = rs._draft_composer.compose(snap, 3, false, [], false)
		if (d8.rewards as Array).size() != 3: count_ok = false; break
		for r in (d8.rewards as Array):
			if String(r.id) == "circuit_pair" or not (r is RewardDefinition): count_ok = false; break
	_ok(count_ok, "shrunken legal pool still fills 3 valid distinct cards")

	# ⑨ 结算期重复获取仍被拒绝（Resolver preflight 双保险）
	var resolver = load("res://scripts/reward/reward_resolver.gd").new(duel)
	var circuit_def = load("res://resources/rewards/defs/circuit_pair.tres")
	var rr = resolver.preflight(circuit_def)
	_ok(not rr.ok and String(rr.reason) == "already_owned",
		"resolver preflight still rejects already-owned circuit (reason=%s)" % String(rr.reason))

	print("OWNED FILTER RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
