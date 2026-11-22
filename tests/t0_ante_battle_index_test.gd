extends Node

# ============================================================================
# T0-6 专项：非战斗节点不得提高敌人强度（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §7）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_ante_battle_index_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 目标：普通/精英按本幕实际战斗序号计算强度；宝箱/事件/营地不占强度序号；
#       Boss 用幕末基准不因非战斗节点提高；日志/UI/存档/探针区分节点序号与战斗序号。
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


func _kind(i: int) -> String:
	return String((_duel.ROOMS[i] as RoomData).kind)


func _act(i: int) -> int:
	return int((_duel.ROOMS[i] as RoomData).act)


# 线性 ante_scale（ria_override=-1）计算某房的强度倍率
func _linear_scale(i: int) -> Dictionary:
	return _duel.run_setup.ante_scale(_duel.ROOMS[i] as RoomData, i, -1)


func _run() -> void:
	_test_layout_assumption()
	_test_special_no_extra_tier()
	_test_camp_no_boss_change()
	_test_boss_mid_act_baseline()
	_test_noncombat_not_counted()
	_test_real_room_hp_unchanged()


# 布局前提：第3房特殊、第7房营地、第8房 Boss（1起算）
func _test_layout_assumption() -> void:
	_check(_kind(2) == "chest" or _kind(2) == "event", "第3房(idx2)是非战斗特殊房（实测 %s）" % _kind(2))
	_check(_kind(5) == "elite", "第6房(idx5)是精英（实测 %s）" % _kind(5))
	_check(_kind(6) == "camp", "第7房(idx6)是营地（实测 %s）" % _kind(6))
	_check(_kind(7) == "boss", "第8房(idx7)是 Boss（实测 %s）" % _kind(7))


# 第3房特殊节点不会使第4房精英(idx3)额外加一层
# 对比 idx3 精英与"若特殊房不存在时应有的战斗序号"：同为同幕第3个战斗房（idx0,1,3）
func _test_special_no_extra_tier() -> void:
	# 同幕第2个战斗房 idx1（普通）与第3个战斗房 idx3（精英）的 ria 应只差 1
	var s1 := _linear_scale(1)
	var s3 := _linear_scale(3)
	var step_hp: float = _duel.BALANCE.ante_room_step_hp
	# s3/s1 的 hp 倍率应等于 step_hp^1（只多一个真实战斗），而非 step_hp^2（多算特殊房）
	var ratio: float = float(s3["hp_scale"]) / float(s1["hp_scale"])
	var expect: float = step_hp
	_check(absf(ratio - expect) < 0.001,
		"第4房精英强度只多一层真实战斗：ratio=%.4f 期望 %.4f（实测 hp %d/%d）" % [ratio, expect, int(s3["hp_scale"] * 1000), int(s1["hp_scale"] * 1000)])


# 第7房营地不改变第8房 Boss 强度：Boss 用幕末基准（本幕战斗房数-1=5）
func _test_camp_no_boss_change() -> void:
	var sboss := _linear_scale(7)
	var step_hp: float = _duel.BALANCE.ante_room_step_hp
	var act_step: float = _duel.BALANCE.ante_act_step_hp
	# 幕末基准：act1 台阶 × step_hp^5（本幕 6 个战斗房，序号 0..5）
	var expect: float = pow(act_step, 0) * pow(step_hp, 5)
	_check(absf(float(sboss["hp_scale"]) - expect) < 0.001,
		"Boss 用幕末基准 step^5（实测 %.4f 期望 %.4f）" % [float(sboss["hp_scale"]), expect])


# Boss 后续幕同样用幕末基准，不因特殊/营地额外提高
func _test_boss_mid_act_baseline() -> void:
	var act2_boss: int = _first_boss_of_act(2)
	var act3_boss: int = _first_boss_of_act(3)
	if act2_boss < 0 or act3_boss < 0:
		_check(false, "找不到 ACT2/ACT3 Boss 房")
		return
	var step_hp: float = _duel.BALANCE.ante_room_step_hp
	var act_step: float = _duel.BALANCE.ante_act_step_hp
	var s2 := _linear_scale(act2_boss)
	var expect2: float = pow(act_step, 1) * pow(step_hp, 5)
	_check(absf(float(s2["hp_scale"]) - expect2) < 0.001,
		"ACT2 Boss 幕末基准 act_step×step^5（实测 %.4f 期望 %.4f）" % [float(s2["hp_scale"]), expect2])
	var s3 := _linear_scale(act3_boss)
	var expect3: float = pow(act_step, 2) * pow(step_hp, 5)
	_check(absf(float(s3["hp_scale"]) - expect3) < 0.001,
		"ACT3 Boss 幕末基准 act_step²×step^5（实测 %.4f 期望 %.4f）" % [float(s3["hp_scale"]), expect3])


# 特殊房本身不占强度序号：特殊房前后同种敌人强度位置差只来自真实战斗
func _test_noncombat_not_counted() -> void:
	# idx1 普通（特殊房前）与 idx4 普通（特殊房后）：中间只有 idx3 精英 1 个真实战斗
	# 战斗序号 idx1=1, idx4=3 → 差 2 层；若错误计入特殊房则差 3 层
	var s1 := _linear_scale(1)
	var s4 := _linear_scale(4)
	var step_hp: float = _duel.BALANCE.ante_room_step_hp
	var ratio: float = float(s4["hp_scale"]) / float(s1["hp_scale"])
	var expect: float = pow(step_hp, 2)
	_check(absf(ratio - expect) < 0.001,
		"特殊房前后普通敌人强度差只来自真实战斗：ratio=%.4f 期望 step²=%.4f" % [ratio, expect])


# 真实开房：第4房精英的实际 enemy_hp_max 必须等于 base_hp × ante_scale(战斗序号) 倍率。
# 证明结算层用的就是修复后的战斗序号倍率（而非 ante_scale 函数正确但结算没用）。
func _test_real_room_hp_unchanged() -> void:
	var room3 := _duel.ROOMS[3] as RoomData
	_duel.start_room_data(room3, 3)
	var hp_actual: int = int(_duel.enemy_hp_max)
	var s := _linear_scale(3)
	var base_hp: int = room3.hp if room3.hp > 0 else (room3.archetype.hp_base if room3.archetype != null else 0)
	var expect_hp: int = int(round(float(base_hp) * float(s["hp_scale"])))
	_check(hp_actual == expect_hp,
		"真实开房 第4房精英 HP=%d = base %d × ante 倍率（期望 %d）" % [hp_actual, base_hp, expect_hp])
	# 战斗序号基准：倍率应只含 step^2（idx0,1,3 三个战斗房），不含特殊房 idx2
	var step: float = _duel.BALANCE.ante_room_step_hp
	_check(absf(float(s["hp_scale"]) - pow(step, 2)) < 0.001,
		"真实开房 第4房精英倍率=step²（不含特殊房额外层，实测 %.4f）" % float(s["hp_scale"]))


func _first_boss_of_act(act: int) -> int:
	for i in _duel.ROOMS.size():
		var r := _duel.ROOMS[i] as RoomData
		if int(r.act) == act and r.kind == "boss":
			return i
	return -1


func _finish() -> void:
	print("---")
	print("T0-6 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
