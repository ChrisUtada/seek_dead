extends Node

# ============================================================================
# G6-2 奖励来源收束测试（2026-11-20）
# 方案 §7：Boss 遗物自动入账（不混入三选一）
# ⚠️ G6-1「精英去堆叠」已回退：安全门实证未通过（移除后 ACT2 422→378 < 396 门槛）。
#    保留精英自动护符+武器作为当前强度曲线支撑，待有替代强度来源再重做去堆叠。
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
