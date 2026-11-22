extends Node

# ============================================================================
# G6-2 奖励来源收束测试（2026-11-20）
# 方案 §7：Boss 遗物自动入账（不混入三选一）
# G6-1 历史：曾尝试移除精英自动奖励但安全门未通过（ACT2 422→378 < 396 门槛），当时回退。
# T1.4 已用「精英强化 Draft」替代自动护符并通过 18 种子 A/B 安全门（ACT2 594→605 ≥396）；
# 精英克制武器仍保留。本测试只覆盖 G6-2 Boss 遗物入账，不覆盖精英护符。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G6 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame

	# G6-2：Boss 遗物不在候选、胜利保证入账
	var boss_room = null
	for r in duel.ROOMS:
		if r != null and String(r.kind) == "boss" and String(r.boss_relic_path) != "":
			boss_room = r
			break
	_ok(boss_room != null, "存在带遗物的 Boss 房用于测试")
	if boss_room != null:
		var cands: Array = duel._reward_system.roll_boss_rewards(boss_room)
		var has_relic := false
		for c in cands:
			if String(c.get("kind", "")) == "boss_relic":
				has_relic = true
		_ok(not has_relic, "G6-2 遗物不混入 Boss 三选一候选")
		duel.run_relics.clear()
		var granted: bool = duel._reward_system.grant_boss_relic(boss_room)
		_ok(granted, "G6-2 遗物保证入账")
		_ok(duel.run_relics.has(String(boss_room.boss_relic_path)), "G6-2 遗物进本局遗物栏")
		_ok(not duel._reward_system.grant_boss_relic(boss_room), "G6-2 重复调用去重")

	print("G6-2 REWARD SOURCE RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
