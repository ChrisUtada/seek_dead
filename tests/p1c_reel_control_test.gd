extends Node

# ============================================================================
# P1-C 滚轴操控奖励测试（headless，2026-11-19）
# 覆盖：
# ① reel_control Adapter 写入 controller.reel_controls
# ② 操控查询接口（snap_per_turn/wide_range/mercy_per_turn）反映奖励授予
# ③ 重复授予被拒绝
# ④ 与技艺同名能力共用查询（不重复实现）
# ⑤ 新局清零
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P1-C FAIL: " + label)


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

	# 初始：无操控奖励 → 操控全 0
	_ok(duel.growth.snap_per_turn() == 0, "initial snap=0")
	_ok(duel.growth.mercy_per_turn() == 0, "initial mercy=0")
	_ok(not duel.reel_controls.has("slow_ramp"), "initial slow_ramp=off")

	# ① 授予 snap 奖励
	var def := RewardDefinition.new()
	def.id = "test_control_snap"
	def.name = "测试吸附"
	def.rarity = "common"
	def.effects = [{"effect_id": "reel_control", "params": {"control_id": "snap"}}]
	var res = rs._draft_resolver.resolve(def)
	_ok(res.ok, "reel_control resolve ok: %s" % res.reason)
	_ok(duel.reel_controls.has("snap"), "snap written to reel_controls")
	# ② 查询接口反映
	_ok(duel.growth.snap_per_turn() > 0, "snap_per_turn reflects reward")

	# ③ 重复授予拒绝
	var dup = rs._draft_resolver.resolve(def)
	_ok(not dup.ok, "duplicate control rejected")

	# ④ B方案：宽判已移除改为 slow_ramp；操控唯一归 reel_controls
	_ok(not duel.growth.grant_perk("wide"), "legacy wide perk no longer exists")
	var slow_def := RewardDefinition.new()
	slow_def.id = "test_slow"
	slow_def.name = "测试缓速"
	slow_def.rarity = "common"
	slow_def.effects = [{"effect_id": "reel_control", "params": {"control_id": "slow_ramp"}}]
	var slow_res = rs._draft_resolver.resolve(slow_def)
	_ok(slow_res.ok, "slow_ramp reward resolves: %s" % slow_res.reason)
	_ok(duel.reel_controls.has("slow_ramp"), "slow_ramp written to reel_controls")

	# ⑤ 新局清零
	duel._reset_run_state()
	_ok(duel.reel_controls.is_empty(), "reel_controls cleared on new run")
	_ok(duel.growth.snap_per_turn() == 0, "snap query back to 0 after reset")

	print("P1C RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
