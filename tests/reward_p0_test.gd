extends Node

# ============================================================================
# 战后三选一重构 · P0 骨架静态测试（headless）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reward_p0_test.tscn
#
# 覆盖（P0 契约）：
# ① RewardDefinition 数据类可实例化、validate() 正确
# ② RunSnapshot / BuildState 值对象可用
# ③ DraftResult / RewardApplyResult 工厂方法可用
# ④ RewardRegistry 可加载（defs 目录为空时返回空数组，不报错）
# ⑤ DraftComposer 可实例化、免费重抽状态规则正确（免费优先、不累积、重置）
# ⑥ RewardEvaluator 评分封顶、治疗情境价值随 HP 分段
# ⑦ class_name 引用均可解析（5 核心模块）
# 不启动 DuelController（P0 骨架不接生产路径）。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P0 FAIL: " + label)


func _run() -> void:
	_test_definition()
	_test_snapshot()
	_test_results()
	_test_registry()
	_test_composer()
	_test_evaluator()
	_test_p1_presentation()
	_test_p1_evaluator_extras()
	_test_p1_composer_sampling()
	_test_p1_definition_rules()
	print("P1 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_definition() -> void:
	var d := RewardDefinition.new()
	d.id = "seed_battle_ready"
	d.name = "战场整备"
	d.rarity = "common"
	d.effects = [{"effect_id": "heal", "params": {}}]
	_ok(d.validate().is_empty(), "valid definition passes validate")
	_ok(d.first_effect_id() == "heal", "first_effect_id")
	_ok(d.has_tag("survival") == false, "has_tag empty")

	var bad := RewardDefinition.new()
	bad.effects = [{"effect_id": "", "params": {}}]
	_ok(not bad.validate().is_empty(), "invalid definition fails validate")


func _test_snapshot() -> void:
	var snap := RunSnapshot.new()
	snap.survival = {"current_hp": 30, "max_hp": 100, "hp_ratio": 0.3}
	snap.economy = {"gold": 12}
	_ok(is_equal_approx(snap.hp_ratio(), 0.3), "hp_ratio read")
	_ok(snap.gold() == 12, "gold read")
	_ok(snap.build_state != null, "BuildState auto-created")
	snap.build_state.build_scores["fire"] = 5
	_ok(snap.build_state.build_score("fire") == 5, "build_score read")


func _test_results() -> void:
	var defs: Array[RewardDefinition] = []
	var draft := DraftResult.new(defs, "draft_test")
	_ok(not draft.is_valid(), "empty draft invalid")
	var d := RewardDefinition.new()
	defs.append(d)
	var draft2 := DraftResult.new(defs, "draft_test2")
	_ok(draft2.is_valid() and draft2.size() == 1, "nonempty draft valid")
	var ok_res := DraftResult.RewardApplyResult.success("r1", "heal", "回血+10")
	_ok(ok_res.ok and ok_res.summary == "回血+10", "apply success factory")
	var fail_res := DraftResult.RewardApplyResult.failure("r1", "heal", "full_hp")
	_ok(not fail_res.ok and fail_res.reason == "full_hp", "apply failure factory")


func _test_registry() -> void:
	# defs 目录尚未建（P2 才填卡），应安全返回空数组而非报错
	var all := RewardRegistry.load_all()
	_ok(all is Array, "Registry load_all returns array")
	_ok(RewardRegistry.validate_all() is Dictionary, "Registry validate_all returns dict")
	_ok(RewardRegistry.count() >= 0, "Registry count non-negative")


func _test_composer() -> void:
	var c := DraftComposer.new(12345)
	# 初次：无免费卡 → 付费
	c.reset_reroll_state(false)
	var r1 := c.request_reroll()
	_ok(r1.get("free") == false, "no free reward -> paid reroll")
	_ok(int(r1.get("cost", 0)) == 5, "first paid cost 5")
	var r2 := c.request_reroll()
	_ok(int(r2.get("cost", 0)) == 10, "paid cost increments")

	# 有免费卡：首次免费，不扣费，不累积
	c.reset_reroll_state(true)
	_ok(c.free_rerolls_remaining == 1, "free reroll initialized")
	var f1 := c.request_reroll()
	_ok(f1.get("free") == true and int(f1.get("cost", 0)) == 0, "free reroll no cost")
	var f2 := c.request_reroll()
	_ok(f2.get("free") == false, "free reroll not accumulate")
	_ok(c.paid_rerolls_used == 1, "free reroll does not touch paid count")


func _test_evaluator() -> void:
	var d := RewardDefinition.new()
	d.id = "heal_test"
	d.base_value = 1.0
	d.effects = [{"effect_id": "heal", "params": {}}]
	var low := RunSnapshot.new()
	low.survival = {"current_hp": 20, "max_hp": 100, "hp_ratio": 0.2}
	var high := RunSnapshot.new()
	high.survival = {"current_hp": 95, "max_hp": 100, "hp_ratio": 0.95}
	var s_low := RewardEvaluator.score(d, low)
	var s_high := RewardEvaluator.score(d, high)
	_ok(s_low > s_high, "heal scores higher at low HP")
	_ok(RewardEvaluator.score_breakdown(d, low).get("context", 0.0) <= 10.0, "context capped")


# ===== P1 测试 =====

func _mk_def(id: String, effect: String, tags: Array[String]) -> RewardDefinition:
	var d := RewardDefinition.new()
	d.id = id
	d.name = id
	d.rarity = "common"
	d.effects = [{"effect_id": effect, "params": {"amount": 2}}]
	d.tags = tags
	d.base_value = 1.0
	return d


func _test_p1_presentation() -> void:
	var defs: Array[RewardDefinition] = []
	var d := _mk_def("seed_edge_polish", "run_power_bonus", ["offense.power"])
	d.rarity = "rare"
	d.desc = "本局伤害提升"
	defs.append(d)
	var draft := DraftResult.new(defs, "draft_view")
	var view := RewardPresentation.draft_to_view(draft, "战利品")
	_ok(bool(view.get("ok", false)), "presentation view ok")
	_ok(String(view.get("quality_name", "")).is_empty(), "no global quality label in new draft")
	var opts: Array = view.get("options", [])
	_ok(opts.size() == 1, "view has options")
	var opt: Dictionary = opts[0]
	_ok(String(opt.get("quality", "")) == "rare", "option quality from card")
	_ok(String(opt.get("quality_name", "")) == "稀有", "quality label mapped")
	_ok(String(opt.get("title", "")) == "seed_edge_polish", "option title")
	_ok(String(opt.get("condition", "")) == "本局生效", "condition from effect")


func _test_p1_evaluator_extras() -> void:
	var snap := RunSnapshot.new()
	snap.survival = {"current_hp": 50, "max_hp": 100, "hp_ratio": 0.5}
	snap.progression = {"room_index": 2, "act": 1, "room_kind": "normal"}
	snap.build_state.build_scores["fire"] = 5
	snap.build_state.tags["build.fire"] = 5.0

	# 新颖性：未形成的构筑种子（build.ice）应给探索分
	var seed := _mk_def("seed_ice", "flame_affinity", ["build.ice"])
	seed.effects = [{"effect_id": "flame_affinity", "params": {}}]
	var b_seed := RewardEvaluator.score_breakdown(seed, snap)
	_ok(float(b_seed.get("novelty", 0.0)) > 0.0, "novelty for unformed build seed")

	# 协同：已形成的火构筑给协同分，且不因多标签重复叠加
	var fire := _mk_def("fire1", "flame_affinity", ["build.fire", "element.fire", "build.fire"])
	fire.effects = [{"effect_id": "flame_affinity", "params": {}}]
	var b_fire := RewardEvaluator.score_breakdown(fire, snap)
	_ok(float(b_fire.get("synergy", 0.0)) > 0.0, "synergy for formed fire build")
	_ok(float(b_fire.get("synergy", 0.0)) <= 8.0, "synergy capped")

	# 风险补偿：带 hp 代价的卡给正分
	var risky := _mk_def("risky", "run_power_bonus", ["risk.high"])
	risky.risk_cost = {"hp": 10}
	var b_risk := RewardEvaluator.score_breakdown(risky, snap)
	_ok(float(b_risk.get("risk", 0.0)) > 0.0, "risk compensation positive")


func _test_p1_composer_sampling() -> void:
	# P2 起 defs 已有 5 张种子卡，compose 应返回 3 张有效卡
	var c := DraftComposer.new(999)
	var snap := RunSnapshot.new()
	snap.survival = {"current_hp": 50, "max_hp": 100, "hp_ratio": 0.5}
	var draft: DraftResult = c.compose(snap, 3, true)
	_ok(draft is DraftResult, "composer returns DraftResult")
	_ok(draft.rewards.size() == 3, "composer returns 3 valid cards (got %d)" % draft.rewards.size())


func _test_p1_definition_rules() -> void:
	# 新字段：规则键名 / 叠加规则 / 风险代价（P1 数据结构完整性）
	var d := _mk_def("rules_test", "flame_affinity", ["build.fire"])
	d.eligibility_rule = "has_build_fire"
	d.context_rule = "income_by_gold"
	d.synergy_rule = "fire"
	d.stack_rule = RewardDefinition.StackRule.LINEAR
	d.max_stack = 3
	d.risk_cost = {"hp": 10}
	_ok(d.validate().is_empty(), "definition with rule fields valid")
	_ok(d.eligibility_rule == "has_build_fire", "eligibility rule stored")
	_ok(d.stack_rule == RewardDefinition.StackRule.LINEAR, "stack rule stored")

	# max_stack=0 非法
	d.max_stack = 0
	_ok(not d.validate().is_empty(), "max_stack 0 invalid")
