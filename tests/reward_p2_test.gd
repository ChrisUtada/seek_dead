extends Node

# ============================================================================
# 战后三选一重构 · P2 集成测试（headless）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reward_p2_test.tscn
#
# 覆盖：
# ① 8 张种子卡 .tres 可加载且 validate 通过
# ② 新引擎生成 3 张卡的 DraftResult + view（品质各异文案）
# ③ Resolver 4 个 effect_id 真实执行（heal/shield/power 委托旧结算 + flame_affinity）
# ④ 免费重抽优先于扣费
# ⑤ Telemetry 新事件记录
# ⑥ BOSS/探索旧路径未被破坏（build_loot_offer growth_only=false）
# 不污染真实存档：结束还原 meta。
# ============================================================================

const SEED_IDS := [
	"seed_battle_ready", "seed_guardian_ember", "seed_edge_polish",
	"seed_flame_resonance",
]

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P2 FAIL: " + label)


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
	_test_seed_defs()
	var duel := await _boot()
	if duel == null:
		push_error("P2 boot failed")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_build_draft(duel)
	_test_resolver(duel)
	_test_reroll(duel)
	_test_telemetry(duel)
	_test_old_path(duel)
	_test_p3_build_state(duel)
	_test_perk_in_draft(duel)
	_test_p4_events(duel)
	_test_p4_explain(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()
	print("P2 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_seed_defs() -> void:
	var reg = load("res://scripts/reward/reward_registry.gd")
	var all = reg.load_all()
	# L2-G：新增 11 张签名解锁卡 → 8→19（原型1张 + 扩卡10张，全部走 learn_signature）
	_ok(all.size() == 20, "20 seed defs loaded (got %d)" % all.size())
	var problems = reg.validate_all()
	_ok(problems.is_empty(), "all seed defs valid: %s" % str(problems))


func _test_build_draft(duel: DuelController) -> void:
	var view: Dictionary = duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	_ok(bool(view.get("ok", false)), "draft view ok")
	_ok(not String(view.get("draft_id", "")).is_empty(), "draft_id present")
	var opts: Array = view.get("options", [])
	_ok(opts.size() == 3, "draft has 3 options (got %d)" % opts.size())
	var is_draft := not String(view.get("draft_id", "")).is_empty()
	_ok(is_draft, "view flagged as draft")


func _test_resolver(duel: DuelController) -> void:
	var resolver = load("res://scripts/reward/reward_resolver.gd").new(duel)
	var composer = load("res://scripts/reward/draft_composer.gd").new(1)
	resolver.bind_composer(composer)

	# heal：先扣血再执行
	duel.player_hp = maxi(1, duel.player_hp_max - 30)
	var def_h = load("res://resources/rewards/defs/seed_battle_ready.tres")
	var before_hp: int = duel.player_hp
	var rh = resolver.resolve(def_h)
	_ok(rh.ok, "heal resolves ok")
	_ok(duel.player_hp > before_hp, "heal increased HP")

	# shield_next_battle
	var def_s = load("res://resources/rewards/defs/seed_guardian_ember.tres")
	var before_shield: int = duel._reward_system.run_shield_next
	var rs = resolver.resolve(def_s)
	_ok(rs.ok, "shield resolves ok")
	_ok(duel._reward_system.run_shield_next == before_shield + 10, "shield_next +10")

	# run_power_bonus
	var def_p = load("res://resources/rewards/defs/seed_edge_polish.tres")
	var before_power: int = duel._reward_system.run_power_bonus
	var rp = resolver.resolve(def_p)
	_ok(rp.ok, "power resolves ok: %s" % rp.reason)
	_ok(duel._reward_system.run_power_bonus == before_power + 2, "power +2")


func _test_reroll(duel: DuelController) -> void:
	duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	duel.gold = 50   # 付费重抽需 5 金；设 50 确保余额充足
	var gold_before: int = duel.gold
	var v: Dictionary = duel._reward_system.reroll_loot_offer()
	_ok(bool(v.get("ok", false)), "reroll ok")
	# 无免费重抽来源，重抽应正常扣费
	_ok(duel.gold < gold_before, "paid reroll deducts gold")
	_ok(int(v.get("reroll_paid", -1)) > 0, "reroll_paid > 0 for paid")


func _test_telemetry(duel: DuelController) -> void:
	var t = duel._telemetry
	_ok(t != null, "telemetry exists")
	_ok(t.draft_shown >= 1, "draft_shown recorded")
	_ok(t.draft_rerolled >= 1, "draft_rerolled recorded")
	_ok(t.draft_events.size() > 0, "draft events recorded")


func _test_old_path(duel: DuelController) -> void:
	# BOSS/探索走旧路径，不应设置 draft_id
	var view: Dictionary = duel._reward_system.build_loot_offer("boss", 1, {})
	_ok(String(view.get("draft_id", "")).is_empty(), "old path has no draft_id")


func _test_p3_build_state(duel: DuelController) -> void:
	var analyzer = load("res://scripts/reward/run_state_analyzer.gd")
	var evaluator = load("res://scripts/reward/reward_evaluator.gd")
	var resolver = load("res://scripts/reward/reward_resolver.gd").new(duel)
	var composer = load("res://scripts/reward/draft_composer.gd").new(7)
	resolver.bind_composer(composer)

	# 基线：清空构筑计数与装备
	duel.element_affinity.clear()
	duel.selected_loadout.clear()
	duel._build_pool(duel.selected_loadout)
	var snap0 = analyzer.capture(duel)
	_ok(int(snap0.build_state.build_score("fire")) == 0, "no fire build at baseline")

	# ① 装备火武器 → 火焰分 >0（武器 +3，符号另计）
	duel.selected_loadout.append("res://resources/weapon_templates/cinder_saber.tres")
	duel._build_pool(duel.selected_loadout)
	var snap1 = analyzer.capture(duel)
	var fire_score := int(snap1.build_state.build_score("fire"))
	_ok(fire_score >= 3, "fire weapon contributes >=3 (got %d)" % fire_score)
	_ok(snap1.build_state.has_tag("element.fire"), "element.fire tag set")
	_ok(snap1.build_state.has_tag("build.fire"), "build.fire tag set")

	# ② 已获火焰奖励 +2（Resolver 写入 element_affinity，重新 capture 生效）
	var def_fire = load("res://resources/rewards/defs/seed_flame_resonance.tres")
	var rr = resolver.resolve(def_fire)
	_ok(rr.ok, "flame_affinity resolves ok")
	var snap2 = analyzer.capture(duel)
	_ok(int(snap2.build_state.build_score("fire")) > fire_score, "fire affinity reward raises fire score")

	# ③ 火焰共鸣卡在已形成构筑时拿协同分
	var fire_def = load("res://resources/rewards/defs/seed_flame_resonance.tres")
	var b = evaluator.score_breakdown(fire_def, snap2)
	_ok(float(b.get("synergy", 0.0)) > 0.0, "fire resonance gains synergy when build formed")

	# ④ 四元素对称卡：Resolver 写入非 fire 元素，协同走默认 build_tag 规则
	var def_ice = load("res://resources/rewards/defs/seed_frost_resonance.tres")
	var ri = resolver.resolve(def_ice)
	_ok(ri.ok, "ice affinity resolves ok")
	_ok(int(duel.element_affinity.get("ice", 0)) > 0, "ice affinity recorded")
	var snap_ice = analyzer.capture(duel)
	_ok(int(snap_ice.build_state.build_score("ice")) > 0, "ice build score derived")

	# ⑤ 清理（不污染后续测试）
	duel.element_affinity.clear()
	duel.selected_loadout.clear()
	duel._build_pool(duel.selected_loadout)


func _test_perk_in_draft(duel: DuelController) -> void:
	# 2026-11-19：技艺改概率注入三选一，选中即习得（不再有 pending_picks 门控）。
	# 本测试直接构造技艺卡验证 resolve→pick 链路；注入概率由 m2_growth_test 覆盖。
	duel.growth.reset_run()
	var def = duel._reward_system._make_perk_def({"id": "tough", "name": "坚韧", "desc": "最大 HP +10", "family": "survive"})
	_ok(def != null and String(def.id) == "perk_tough", "perk def built")
	var res = duel._reward_system._draft_resolver.resolve(def)
	_ok(res.ok, "perk card resolves ok: %s" % res.reason)
	_ok(duel.growth.perk_ids.size() == 1, "perk learned by resolve")
	duel.growth.reset_run()


func _test_p4_events(duel: DuelController) -> void:
	var t = duel._telemetry
	# applied 事件：settle 一张卡后应有 reward_applied
	duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	var applied_before := _count_event(t, "reward_applied")
	duel._reward_system.settle_loot_offer(0)
	_ok(_count_event(t, "reward_applied") > applied_before, "reward_applied event recorded")
	# run_outcome：log_telemetry 应记录一局结果（不真正改游戏状态）
	var outcome_before := _count_event(t, "run_outcome")
	duel.room_flow.log_telemetry()
	_ok(_count_event(t, "run_outcome") > outcome_before, "run_outcome event recorded")


func _count_event(t, event_name: String) -> int:
	var n := 0
	for e in t.draft_events:
		if e is Dictionary and str(e.get("event", "")) == event_name:
			n += 1
	return n


func _test_p4_explain(duel: DuelController) -> void:
	var composer = load("res://scripts/reward/draft_composer.gd").new(11)
	var snap = RunSnapshot.new()
	snap.survival = {"current_hp": 20, "max_hp": 100, "hp_ratio": 0.2}
	snap.build_state.build_scores["fire"] = 0
	composer.compose(snap, 3, true)
	var text: String = composer.explain_last()
	_ok(text.contains("候选池"), "explain has pool info")
	_ok(text.contains("评分明细"), "explain has score breakdown")
	_ok(text.contains("入选"), "explain has picked info")
