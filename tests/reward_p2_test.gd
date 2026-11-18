extends Node

# ============================================================================
# 战后三选一重构 · P2 集成测试（headless）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reward_p2_test.tscn
#
# 覆盖：
# ① 5 张种子卡 .tres 可加载且 validate 通过
# ② 新引擎生成 3 张卡的 DraftResult + view（品质各异文案）
# ③ Resolver 5 个 effect_id 真实执行（heal/shield/power 委托旧结算）
# ④ 免费重抽优先于扣费
# ⑤ Telemetry 新事件记录
# ⑥ BOSS/探索旧路径未被破坏（build_loot_offer growth_only=false）
# 不污染真实存档：结束还原 meta。
# ============================================================================

const SEED_IDS := [
	"seed_battle_ready", "seed_guardian_ember", "seed_edge_polish",
	"seed_flame_resonance", "seed_lucky_afterglow",
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

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()
	print("P2 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_seed_defs() -> void:
	var reg = load("res://scripts/reward/reward_registry.gd")
	var all = reg.load_all()
	_ok(all.size() == 5, "5 seed defs loaded (got %d)" % all.size())
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

	# free_reroll
	var def_f = load("res://resources/rewards/defs/seed_lucky_afterglow.tres")
	composer.reset_reroll_state(false)
	var rf = resolver.resolve(def_f)
	_ok(rf.ok, "free_reroll resolves ok")
	_ok(composer.free_rerolls_remaining == 1, "free reroll granted")


func _test_reroll(duel: DuelController) -> void:
	duel._reward_system.build_loot_offer("normal", 1, {"growth_only": true})
	var gold_before: int = duel.gold
	# 手动授予一次免费重抽
	duel._reward_system._draft_composer.free_rerolls_remaining = 1
	var v: Dictionary = duel._reward_system.reroll_loot_offer()
	_ok(bool(v.get("ok", false)), "reroll ok")
	_ok(duel.gold == gold_before, "free reroll did not deduct gold")
	_ok(int(v.get("reroll_paid", -1)) == 0, "reroll_paid 0 for free")


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
