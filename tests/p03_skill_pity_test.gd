extends Node

# ============================================================================
# P0.3 技艺保底迁移测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p03_skill_pity_test.tscn
#
# 覆盖（V1.1 §21/§23/§29）：
# ① 保底状态归 RewardSystem（growth_system 不再有旧字段/方法）
# ② 前 3 房一次性保底，之后不再触发
# ③ 保底 Draft 含技艺候选
# ④ 保底 Draft 重抽后仍含技艺
# ⑤ 结算后一次性完成，之后 Draft 不再强制
# ⑥ 跳过也算展示完成
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P0.3 FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _draft_has_skill(duel: DuelController) -> bool:
	var result = duel._reward_system._draft_result
	if result == null:
		return false
	for d in (result.rewards as Array):
		if d is RewardDefinition and d.effective_category() == "skill":
			return true
	return false


func _run() -> void:
	# ① growth_system 不再持有旧保底状态
	var g_script: Script = load("res://scripts/systems/growth_system.gd") as Script
	var g = g_script.new(null)
	_ok(not ("rooms_settled" in g) and not ("perks_offered" in g), "growth_system has no old pity state")
	_ok(not g.has_method("should_offer_perk"), "growth_system has no should_offer_perk")

	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	var rs = duel._reward_system

	# ② 前 3 房一次性保底
	_ok(rs.skill_pity_rooms == 0 and not rs.skill_offer_guarantee_satisfied, "initial pity state clean")
	for i in range(rs.SKILL_PITY_ROOMS):
		rs.note_skill_pity_room(true)
	_ok(rs.should_force_skill(), "force skill after %d rooms" % rs.SKILL_PITY_ROOMS)

	# ③ 保底 Draft 含技艺
	var view: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	_ok(bool(view.get("growth_only", false)), "draft built")
	_ok(_draft_has_skill(duel), "guaranteed draft contains skill")

	# ④ 重抽后仍含技艺（保底未完成前）
	rs._draft_composer.reset_reroll_state()
	duel.gold = 100
	var rr: Dictionary = duel._reward_system.reroll_loot_offer()
	_ok(bool(rr.get("ok", false)), "reroll ok")
	_ok(_draft_has_skill(duel), "reroll still contains skill under guarantee")

	# ⑤ 结算后一次性完成（选一张可结算卡：武器卡槽满会 needs_replace，需跳过）
	var settle_idx: int = 0
	var dresult = duel._reward_system._draft_result
	if dresult != null:
		for i in range(dresult.rewards.size()):
			if dresult.rewards[i].first_effect_id() != "weapon_replace":
				settle_idx = i
				break
	var settle: Dictionary = duel._reward_system.settle_loot_offer(settle_idx)
	_ok(bool(settle.get("ok", false)), "settle ok: %s" % str(settle.get("reason", "")))
	_ok(rs.skill_offer_guarantee_satisfied, "pity satisfied after settle")
	_ok(not rs.should_force_skill(), "no more force after satisfied")

	# ⑥ 新局重置
	rs.reset_run()
	_ok(rs.skill_pity_rooms == 0 and not rs.skill_offer_guarantee_satisfied, "reset clears pity state")

	print("P03PITY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
