extends Node

# ============================================================================
# P1-B 牌谱规则强化测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p1b_pattern_bonus_test.tscn
#
# 覆盖：
# ① pattern_bonus Adapter 写入 controller.pattern_param_overrides
# ② 非法 pattern_id 被拒绝
# ③ PatternEffects._apply_overrides 合并不污染原 .tres
# ④ 合并后 effect_params 反映 delta，原始 pattern 不变
# ⑤ 新局清零 override
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P1-B FAIL: " + label)


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

	# ① 合法 pattern_id 写入 override
	var ok_def := RewardDefinition.new()
	ok_def.id = "test_rule"
	ok_def.name = "测试规则"
	ok_def.rarity = "common"
	ok_def.effects = [{"effect_id": "pattern_bonus", "params": {
		"pattern_id": "SIG02", "param": "burn_extra", "delta": 1}}]
	var res = rs._draft_resolver.resolve(ok_def)
	_ok(res.ok, "pattern_bonus resolve ok: %s" % res.reason)
	_ok(res.summary.find("%+g") == -1 and res.summary.find("+1.00") != -1,
		"summary formats delta with %%+.2f (no unformatted %%+g): %s" % res.summary)
	_ok(duel.pattern_param_overrides.has("SIG02"), "override written for SIG02")
	_ok(int(duel.pattern_param_overrides["SIG02"].get("burn_extra", 0)) == 1, "burn_extra delta=1")

	# ② 非法 pattern_id 拒绝
	var bad := RewardDefinition.new()
	bad.id = "test_rule_bad"
	bad.name = "测试规则错误"
	bad.rarity = "common"
	bad.effects = [{"effect_id": "pattern_bonus", "params": {
		"pattern_id": "NO_SUCH_PATTERN", "param": "burn_extra", "delta": 1}}]
	var bad_res = rs._draft_resolver.resolve(bad)
	_ok(not bad_res.ok, "unknown pattern rejected")
	_ok(bad_res.reason == "unknown_pattern", "reason=unknown_pattern")

	# ③/④ 合并视图不污染原资源
	var pattern = duel._pattern_system.get_pattern("SIG02")
	_ok(pattern != null, "SIG02 pattern exists")
	var burn_before := int(pattern.effect_params.get("burn_extra", 0))
	var ctx := {"ctrl": duel}
	var pe = load("res://scripts/battle/pattern_effects.gd")
	var view = pe._apply_overrides(pattern, ctx)
	_ok(view != null, "override view created")
	_ok(int(view.effect_params.get("burn_extra", 0)) == burn_before + 1,
		"merged burn_extra = base + delta (%d -> %d)" % [burn_before, int(view.effect_params.get("burn_extra", 0))])
	_ok(int(pattern.effect_params.get("burn_extra", 0)) == burn_before, "original .tres params unchanged")

	# ⑤ 新局清零
	duel._reset_run_state()
	_ok(duel.pattern_param_overrides.is_empty(), "override cleared on new run")

	print("P1B RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
