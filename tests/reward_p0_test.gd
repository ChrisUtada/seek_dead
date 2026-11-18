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
	print("P0 RESULT: %d checks, %d fails" % [_checks, _fails])
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
