extends Node

# P0-FINAL 复现探针（修改前）：验证当前从 20% 以上 HP 被真实扣血路径压到 0 时的绕过。
# 只读复现，不改生产代码。运行于隔离 APPDATA。

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("P0REPRO|RESULT checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(0)   # 复现探针恒 0 退出，仅打印，不阻断

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("P0REPRO|%s|%s" % ["PASS" if cond else "FAIL", msg])

func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel

func _start_room(duel: DuelController, room_name: String):
	for r in duel.ALL_ROOMS:
		if String(r.name) == room_name:
			duel.ROOMS.clear()
			duel.ROOMS.append(r)
			duel.start_room_data(r, 0, 0, false)
			return duel.current_gimmick
	return null

func _run() -> void:
	var duel := await _boot()
	var g = _start_room(duel, "勇者的阴影")
	if g == null:
		print("P0REPRO|FATAL no shadow gimmick")
		return
	duel.enemy_hp_max = 2916
	# 场景1：满血一击巨额直击压到 0（模拟大额伤害，绕过 on_damaged 的阶段早退）
	duel.enemy_hp = 2916
	duel.combat.apply_enemy_damage(99999, true)   # 穿透大额直击
	duel.apply_enemy_hp_floor()
	print("P0REPRO|SC1 big-hit: enemy_hp=%d phase2=%s phase3=%s" % [duel.enemy_hp, str(g._phase2), str(g._phase3)])
	_check(duel.enemy_hp == 1, "满血巨额直击应钳制为1（修复后）")

	# 场景2：P2 中途一次性压到 0（enemy_hp 处于 66% 以下、20% 以上，直击）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 600   # 约20.6%，处于 P2、P3 阈值之上
	duel.combat.apply_enemy_damage(99999, true)
	duel.apply_enemy_hp_floor()
	print("P0REPRO|SC2 p2-lethal: enemy_hp=%d phase2=%s phase3=%s" % [duel.enemy_hp, str(g._phase2), str(g._phase3)])
	_check(duel.enemy_hp == 1, "P2 中途致死应钳制为1（修复后）")

	# 场景3：DoT 压到 0（直接扣 HP，不调 on_damaged）
	_start_room(duel, "勇者的阴影")
	g = duel.current_gimmick
	duel.enemy_hp_max = 2916
	duel.enemy_hp = 600
	duel.enemy_status["burn"] = 500   # 巨额 DoT
	duel.combat.tick_status()
	duel.apply_enemy_hp_floor()
	print("P0REPRO|SC3 dot-lethal: enemy_hp=%d phase2=%s phase3=%s" % [duel.enemy_hp, str(g._phase2), str(g._phase3)])
	_check(duel.enemy_hp == 1, "DoT 致死应钳制为1（修复后）")

	duel.queue_free()
	await get_tree().process_frame
