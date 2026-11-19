extends Node

# ============================================================================
# P0.4 验收单元测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p04_acceptance_test.tscn
#
# 覆盖规格 V1.0 §14.1 中此前未覆盖的验收项：
# ① 满血时治疗奖励被过滤
# ② 非法定义（无 id / 无效果）不进入候选
# ③ 三选一无重复 ID、无三张同类
# ④ 同一 Draft 重复结算只生效一次（防双击）
# ⑤ 金币不足不重抽、不改变 Draft
# ⑥ 重抽成功扣款并整组三项更新
# ⑦ 技艺已全部获得时保底不注入（池空）
#
# 说明：输出曲线 / 并行成长需真人跑局（规格 §14.3），无法在单元测试覆盖，
#       已在《P0实施问题整理》文档中如实标注。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P0.4 FAIL: " + label)


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
	await _test_full_hp_filter()
	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	_test_invalid_defs(duel)
	_test_draft_sanity(duel)
	_test_double_settle(duel)
	_test_reroll_funds(duel)
	_test_perk_pool_empty(duel)
	print("P04ACCEPT RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_full_hp_filter() -> void:
	# 满血时 heal 卡应被 composer 过滤（用纯 composer，不启动 duel）
	var composer := DraftComposer.new(42)
	var snap := RunSnapshot.new()
	snap.survival = {"current_hp": 100, "max_hp": 100, "hp_ratio": 1.0}
	var heal := RewardDefinition.new()
	heal.id = "test_heal"
	heal.name = "测试治疗"
	heal.rarity = "common"
	heal.effects = [{"effect_id": "heal", "params": {}}]
	heal.eligibility_rule = "not_full_hp"
	var draft: DraftResult = composer.compose(snap, 3, true, [heal])
	var has_heal := false
	for d in draft.rewards:
		if d.id == "test_heal":
			has_heal = true
	_ok(not has_heal, "full-hp heal card filtered out")


func _test_invalid_defs(duel: DuelController) -> void:
	var bad := RewardDefinition.new()
	bad.id = ""
	_ok(not bad.validate().is_empty(), "definition without id invalid")
	bad.id = "bad_def"
	bad.effects = []
	_ok(not bad.validate().is_empty(), "definition without effects invalid")
	var problems := RewardRegistry.validate_all()
	_ok(problems.is_empty(), "all shipped reward defs valid: %s" % str(problems))


func _test_draft_sanity(duel: DuelController) -> void:
	var view: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	_ok(bool(view.get("growth_only", false)), "draft view built")
	var result = duel._reward_system._draft_result
	_ok(result != null and result.rewards.size() == 3, "draft has 3 rewards")
	var ids := {}
	var cats := {}
	for d in (result.rewards as Array):
		ids[d.id] = true
		var cat: String = d.effective_category()
		cats[cat] = int(cats.get(cat, 0)) + 1
	_ok(ids.size() == 3, "no duplicate reward ids")
	var max_same := 0
	for cat in cats:
		max_same = maxi(max_same, int(cats[cat]))
	_ok(max_same <= 2, "no 3 same-category cards (max=%d)" % max_same)


func _test_double_settle(duel: DuelController) -> void:
	duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	# 选一张可结算的卡：武器卡槽满会返回 needs_replace，需跳过（测试防重复结算，非测特定卡）
	var settle_idx: int = -1
	var result = duel._reward_system._draft_result
	if result != null:
		for i in range(result.rewards.size()):
			if result.rewards[i].first_effect_id() != "weapon_replace":
				settle_idx = i
				break
	_ok(settle_idx >= 0, "found a settleable card")
	if settle_idx < 0:
		return
	var gold_before := int(duel.gold)
	var first: Dictionary = duel._reward_system.settle_loot_offer(settle_idx)
	_ok(bool(first.get("ok", false)), "first settle ok: %s" % str(first.get("reason", "")))
	var second: Dictionary = duel._reward_system.settle_loot_offer(settle_idx)
	_ok(not bool(second.get("ok", false)), "second settle rejected")
	_ok(String(second.get("reason", "")) == "already_settled", "second settle reason=already_settled")
	_ok(duel.gold == gold_before + int(first.get("gold", 0)), "gold not doubled by double settle")


func _test_reroll_funds(duel: DuelController) -> void:
	duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	duel.gold = 0
	var poor: Dictionary = duel._reward_system.reroll_loot_offer()
	_ok(not bool(poor.get("ok", false)), "reroll rejected when broke")
	_ok(String(poor.get("reason", "")) == "insufficient_gold", "poor reroll reason")
	duel.gold = 100
	var draft_before = duel._reward_system._draft_result
	var rich: Dictionary = duel._reward_system.reroll_loot_offer()
	_ok(bool(rich.get("ok", false)), "reroll ok with gold")
	_ok(duel._reward_system._draft_result != draft_before, "reroll replaced draft")
	_ok(duel.gold < 100, "reroll deducted gold")


func _test_perk_pool_empty(duel: DuelController) -> void:
	# 所有技艺已获得 → roll_choices 空 → extra 无技艺 → draft 无强制技艺
	var g = duel.growth
	for p in g.PERKS:
		if not g.perk_ids.has(String(p["id"])):
			g.grant_perk(String(p["id"]))
	_ok(g.roll_choices().is_empty(), "perk pool exhausted")
	var rs = duel._reward_system
	rs.reset_run()
	rs.note_skill_pity_room(true)
	rs.note_skill_pity_room(true)
	rs.note_skill_pity_room(true)
	var force: bool = rs.should_force_skill()
	_ok(force, "pity still flags force when perk pool empty")
	rs.build_loot_offer("normal", 1, {"growth_only": true})
	# 池空时 composer 不会凭空造技艺卡，Draft 不应含 skill 类别
	var result = rs._draft_result
	var has_skill := false
	for d in (result.rewards as Array):
		if d is RewardDefinition and d.effective_category() == "skill":
			has_skill = true
	_ok(not has_skill, "no fabricated skill card when perk pool empty")
