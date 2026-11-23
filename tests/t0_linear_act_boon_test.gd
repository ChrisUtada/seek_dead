extends Node

# ============================================================================
# T0-5 专项：线性模式幕间锻魂断链（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §6）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_linear_act_boon_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 目标：线性模式进入 ACT2/ACT3 首个房间时触发一次对应锻魂（+8 符号效能 / +20 最大HP与回血），
#       触发依据是真实 ACT 变化而非房间下标；沿用 granted_acts 幂等；ACT1 开局、
#       最终 Boss 追加房不额外发；保留地图兼容路径不双发。
# ============================================================================

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.board_config.enabled = false
	_duel.shop_run_seed = 20261123
	_duel._confirm_loadout()
	await get_tree().process_frame
	await _run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _boon_state() -> Dictionary:
	return {
		"power": int(_duel._reward_system.run_power_bonus),
		"hp_max": int(_duel.player_hp_max),
		"hp": int(_duel.player_hp),
	}


# 找某幕第一个房间的下标（按 RoomData.act）
func _first_room_of_act(act: int) -> int:
	for i in _duel.ROOMS.size():
		if int((_duel.ROOMS[i] as RoomData).act) == act:
			return i
	return -1


# 线性模式：从 idx 通过真实 on_next_room_pressed 进入下一房
func _advance_linear_from(idx: int) -> void:
	_duel.room_index = idx
	_duel.current_act = int((_duel.ROOMS[idx] as RoomData).act)
	_duel.game_state = _duel.FlowState.PLAYING
	_duel._busy = false
	_duel.in_interroom = false
	_duel.room_flow.on_next_room_pressed()
	# M-02b：跨幕首房前会显示章节头，模拟玩家确认继续（锻魂/进房在回调里完成）
	if _duel._chapter_intro != null and _duel._chapter_intro.visible:
		_duel._chapter_intro.continue_btn.pressed.emit()
	await get_tree().process_frame


func _run() -> void:
	await _test_act1_no_boon()
	await _test_act1_to_act2()
	await _test_act2_to_act3()
	await _test_idempotent_same_act()
	await _test_final_boss_no_extra()


# ACT1 开局不发放（进第一房不触发）
func _test_act1_no_boon() -> void:
	_duel.growth.reset_run()
	var before := _boon_state()
	_duel.room_index = 0
	_duel.current_act = 1
	_duel.game_state = _duel.FlowState.PLAYING
	_duel.start_room_data(_duel.ROOMS[0], 0)
	var after := _boon_state()
	_check(after["power"] == before["power"], "ACT1 开局 power 不变（实测 %d）" % after["power"])
	_check(after["hp_max"] == before["hp_max"], "ACT1 开局 hp_max 不变（实测 %d）" % after["hp_max"])
	_check(not _duel.growth.granted_acts.has(1), "ACT1 未记入 granted_acts")


# ACT1→ACT2：真实入口进入 ACT2 首房，触发一次
func _test_act1_to_act2() -> void:
	_duel.growth.reset_run()
	var act1_last: int = _first_room_of_act(2) - 1
	_check(act1_last >= 0, "找到 ACT1 最后一房（idx %d）" % act1_last)
	var before := _boon_state()
	await _advance_linear_from(act1_last)
	var after := _boon_state()
	_check(int(_duel.current_act) == 2, "ACT1→ACT2 当前 ACT=2（实测 %d）" % _duel.current_act)
	_check(after["power"] == before["power"] + _duel.growth.ACT_BOON_POWER, "ACT1→ACT2 power +8（实测 %d）" % (after["power"] - before["power"]))
	# T1.7 收口：锻魂只发 +8 符号伤害，不再改最大 HP/当前 HP
	_check(after["hp_max"] == before["hp_max"], "ACT1→ACT2 hp_max 不变（实测 %d）" % (after["hp_max"] - before["hp_max"]))
	_check(after["hp"] == before["hp"], "ACT1→ACT2 当前 HP 不变（实测 %d）" % (after["hp"] - before["hp"]))
	_check(_duel.growth.granted_acts.has(2), "ACT1→ACT2 granted_acts 含 2")


# ACT2→ACT3：只发 ACT3 对应一次
func _test_act2_to_act3() -> void:
	# 承接上一步（ACT2 已发放）；从 ACT2 最后一房进 ACT3
	_duel.growth.reset_run()
	_duel.growth.grant_act_boon(2)   # 先发 ACT2（模拟已过 ACT2）
	var before := _boon_state()
	var act2_last: int = _first_room_of_act(3) - 1
	_check(act2_last >= 0, "找到 ACT2 最后一房（idx %d）" % act2_last)
	await _advance_linear_from(act2_last)
	var after := _boon_state()
	_check(int(_duel.current_act) == 3, "ACT2→ACT3 当前 ACT=3（实测 %d）" % _duel.current_act)
	_check(after["power"] == before["power"] + _duel.growth.ACT_BOON_POWER, "ACT2→ACT3 只发 ACT3 一次（实测 %d）" % (after["power"] - before["power"]))
	_check(_duel.growth.granted_acts.has(3), "ACT2→ACT3 granted_acts 含 3")


# 同一幕重复进入不重复发
func _test_idempotent_same_act() -> void:
	_duel.growth.reset_run()
	_duel.growth.grant_act_boon(2)
	var before := _boon_state()
	# 在 ACT2 内连续进入同幕房间（用 on_next_room_pressed 从 ACT2 首房往后）
	var act2_first: int = _first_room_of_act(2)
	await _advance_linear_from(act2_first)
	var after := _boon_state()
	_check(after["power"] == before["power"], "同幕重复进入 power 不变（实测 %d）" % after["power"])
	_check(after["hp_max"] == before["hp_max"], "同幕重复进入 hp_max 不变（实测 %d）" % after["hp_max"])


# 最终 Boss 追加房不额外发（act 与 ACT3 相同，幂等守卫挡住）
func _test_final_boss_no_extra() -> void:
	_duel.growth.reset_run()
	_duel.growth.grant_act_boon(3)
	var before := _boon_state()
	# 找到 final_boss 房（若存在）
	var final_idx: int = -1
	for i in _duel.ROOMS.size():
		if bool((_duel.ROOMS[i] as RoomData).final_boss):
			final_idx = i
			break
	if final_idx < 0:
		_check(true, "本局无最终 Boss 追加房，跳过")
		return
	var prev_idx: int = final_idx - 1
	await _advance_linear_from(prev_idx)
	var after := _boon_state()
	_check(after["power"] == before["power"], "最终 Boss 追加房 power 不额外增加（实测 %d）" % after["power"])
	_check(after["hp_max"] == before["hp_max"], "最终 Boss 追加房 hp_max 不额外增加（实测 %d）" % after["hp_max"])


func _finish() -> void:
	print("---")
	print("T0-5 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
