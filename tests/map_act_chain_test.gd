extends Node

# ============================================================================
# 地图巡逻诱导 · Step 0.5 · 配置驱动多幕终局定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md §6 Step 0.5 自动出口、§7
#
# 覆盖：acts=1 唯一 BOSS 为 final；acts=3 仅 ACT III 为 final，ACT I/II 可继续；
#       三幕封顶无 ACT IV；正式入口默认关闭；旧双开关与旧三幕链不回归。
#
# 本套只调用 MapBoardBuilder，不改产品默认入口，不跳过 g7_run3_test / loot_explore_test。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BUILDER := "res://scripts/board/map_board_builder.gd"
const SEED := 20261110

var _checks := 0
var _fails := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPACT|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await _frames(3)
	var cfg = duel.board_config
	var acts_was: int = int(cfg.acts)
	var builder = load(BUILDER).new(duel)

	print("=== A 配置驱动终局 ===")
	_test_final_by_acts(builder, cfg)
	print("=== B 三幕封顶 ===")
	_test_no_act_four(builder, duel)
	print("=== C 旧入口与旧三幕链不回归 ===")
	_test_legacy_intact(cfg, duel)
	print("=== D 正式入口默认关闭 ===")
	_test_dev_gate(cfg)

	cfg.acts = acts_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPACT|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _boss_final(data: Dictionary) -> bool:
	var boss: Dictionary = data["by_id"][data["boss_id"]]
	return bool(boss.get("final", false))


func _non_boss_final_count(data: Dictionary) -> int:
	var n := 0
	for node in data["nodes"]:
		if String(node["type"]) != "boss" and bool(node.get("final", false)):
			n += 1
	return n


func _test_final_by_acts(builder, cfg) -> void:
	cfg.acts = 1
	var single: Dictionary = builder.build(1, SEED, 1)
	_check(_boss_final(single), "acts=1：唯一一幕的 BOSS 是 final")
	_check(int(single["total_acts"]) == 1, "acts=1：total_acts 归一化为 1")
	_check(_non_boss_final_count(single) == 0, "acts=1：非 BOSS 节点都不标 final")

	cfg.acts = 3
	var finals: Array = []
	for act in [1, 2, 3]:
		var d: Dictionary = builder.build(act, SEED, 3)
		finals.append(_boss_final(d))
		_check(_non_boss_final_count(d) == 0, "ACT%d：非 BOSS 节点都不标 final" % act)
		_check(int(d["act"]) == act, "ACT%d：幕号写进节点" % act)
	_check(finals == [false, false, true],
		"acts=3：仅 ACT III 的 BOSS 是 final（%s）" % str(finals))
	_check(not finals[0] and not finals[1], "ACT I / ACT II 可以进入下一幕")


func _test_no_act_four(builder, duel: DuelController) -> void:
	_check(builder.normalized_acts(0) == 1, "acts=0 归一化为 1（下限）")
	_check(builder.normalized_acts(3) == 3, "acts=3 保持 3")
	_check(builder.normalized_acts(4) == 3, "acts=4 归一化为 3，不产生 ACT IV")
	_check(builder.MAX_ACTS == 3, "MAX_ACTS 冻结为 3")
	var over: Dictionary = builder.build(3, SEED, 99)
	_check(int(over["total_acts"]) == 3, "build(99 幕) 归一化后 total_acts=3")
	_check(_boss_final(over), "归一化后 ACT III BOSS 仍是 final")
	# 旧三幕链的幕数入口未被本步改动。
	duel.board_config.acts = 3
	_check(duel.run_act_count() == 3, "旧 run_act_count() 仍为 3")


func _test_legacy_intact(cfg, duel: DuelController) -> void:
	# Step 0.5 自动出口：g7_run3_test / loot_explore_test / g8_loadout_layout_test 持续有效。
	# 本步不收敛 board_system / board_screen / board_config，因此双开关与旧模型入口必须还在。
	# 2026-11-14 收敛：14×9 替换两套旧模型，双开关已删除，只保留单一地图入口。
	_check(not cfg.has_method("use_grid"), "use_grid() 双开关已删除")
	_check(not cfg.has_method("layout_mode") and not ("layout_mode" in cfg), "layout_mode 已删除")
	_check(cfg.has_method("is_active"), "board_config.is_active() 入口保留")
	_check(int(cfg.map_seed) > 0, "固定地图种子 map_seed 在位（%d）" % int(cfg.map_seed))
	_check(duel.board != null, "BoardSystem 实例仍在（14×9 门面）")
	_check(duel.board.has_method("generate"), "BoardSystem.generate() 入口保留")


func _test_dev_gate(cfg) -> void:
	# 收敛后不再需要「开发入口」门闸：地图就是唯一路径，由 is_active() 控制开/关。
	_check(not bool(cfg.enabled), "棋盘默认不在开局启用")
	_check(not cfg.is_active(), "默认走线性房间")
	cfg.enabled = true
	_check(cfg.is_active(), "整备页可开启 14×9 地图")
	cfg.enabled = false
	_check(not cfg.is_active(), "可复位回线性，不写存档")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_fails += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
