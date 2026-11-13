extends Node

# ============================================================================
# 转轮手感优化 · Step 2 定向测试（2026-11-12）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reel_absorb_test.tscn
#
# 覆盖（真实 DuelController + ReelSpinView，但不结算奖励）：
#   1. 停轮请求先记录：格子不立即改写，吸附目标 = 按停时的视觉中心
#   2. 吸附期间重复停轮被拒绝，只结算一次
#   3. 吸附完成后落子，格子符号 = 吸附目标，遥测只记一次
#   4. 自动（forced）与手动停轮共用吸附入口
#   5. 多列同时吸附：全部完成前不发 spin_finished，完成后只发一次
#   6. 停轮吸附全程不消耗全局 RNG
# ============================================================================

const TARGET_PATH := "res://resources/symbols/fire_slash.tres"

var _checks := 0
var _fails := 0
var _save_backup := {}
var _have_save_backup := false


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	_have_save_backup = true
	await _run()
	_restore_save()
	print("---")
	print("REELABSORB|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _restore_save() -> void:
	if not _have_save_backup:
		return
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("REELABSORB|FAIL|" + msg)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _setup(duel: DuelController) -> void:
	var out: Array[String] = []
	for w in ["fire_sword", "ice_staff"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(w + ".tres"):
				out.append(p)
				break
	duel.selected_loadout.assign(out)
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	duel.reel_system._timer.stop()
	duel.readability.apply_preset("visual")   # 落点对齐视觉中心，便于核对吸附目标
	# 清掉普通怪早期特性可能注入的干扰，让用例只验证吸附本身。
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.player_frost = 0
	duel.frozen_cols.clear()


# 三列统一成 3 格带子：0 废铁 / 1 火斩 / 2 金币，便于核对落点。
func _stack_strips(duel: DuelController) -> void:
	var trash = duel.TRASH_SYMBOL
	var gold = duel.GOLD_SYMBOL
	var fire = load(TARGET_PATH)
	var one := [[trash, "none"], [fire, "fire"], [gold, "none"]]
	duel.reel_system.reel_strips = [one.duplicate(true), one.duplicate(true), one.duplicate(true)]


func _arm_reel(duel: DuelController, r: int, index: int, frac: float) -> void:
	var sv = duel.hud.cell_spin_views[r][0]
	sv._active = true
	sv._index = index
	sv._frac = frac


func _run() -> void:
	var duel: DuelController = await _boot()
	_setup(duel)
	_stack_strips(duel)
	var rs = duel.reel_system

	# 1. 手动按停：先记录、不写格子
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	duel.grid[0][0] = duel.TRASH_SYMBOL
	_arm_reel(duel, 0, 0, 0.7)   # 视觉中心 = 1
	var stop_before: int = int(duel._telemetry.stop_total)
	rs.stop_next_reel()
	_check(rs.is_absorbing(0) and not rs.reel_stopped[0], "按停后先进入吸附，不立即落子")
	_check(rs.absorb_target(0) == 1, "吸附目标 = 按停时的视觉中心")
	_check(rs.is_busy(0), "吸附中的列视为 busy")
	_check(duel.grid[0][0] == duel.TRASH_SYMBOL, "吸附中不写格子结果")

	# 2. 吸附中重复停轮：拒绝，不得改目标或重复结算
	rs.stop_next_reel()
	rs.lock_reel(0)
	rs.lock_reel(0)
	_check(rs.absorb_target(0) == 1, "重复停轮不改变吸附目标")
	_check(int(duel._telemetry.stop_total) == stop_before, "吸附完成前不记停轮结算")

	# 3. 吸附完成：落子、结算一次
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[0], "吸附完成后落子")
	_check(duel.grid[0][0].resource_path == TARGET_PATH, "格子符号 = 吸附目标")
	_check(int(duel._telemetry.stop_total) == stop_before + 1, "遥测只记录一次停轮")
	_check(rs.absorb_progress(0) < 0.0, "完成后不再报告吸附进度")

	# 4. 自动停轮（forced）与手动共用同一吸附入口
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	_arm_reel(duel, 0, 0, 0.0)   # 视觉中心 = 0；forced 不看视觉
	var forced_before: int = int(duel.readability.forced_stops)
	rs.stop_next_reel(false, "forced")
	_check(rs.is_absorbing(0), "自动停轮也先进入吸附")
	_check(rs.absorb_target(0) == 0, "自动停轮按逻辑游标记录落点")
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[0], "自动停轮吸附后落子")
	_check(duel.grid[0][0] == duel.TRASH_SYMBOL, "自动停轮落点为逻辑游标符号")
	_check(int(duel.readability.forced_stops) == forced_before + 1, "自动停轮只结算一次")

	# 5. 三列同时吸附：全部完成前不发 spin_finished，完成后只发一次
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, false, false])
	rs._pending_stops.clear()
	for r in 3:
		_arm_reel(duel, r, 0, 0.2)
	var finished := [0]
	var on_finished := func() -> void: finished[0] += 1
	rs.spin_finished.connect(on_finished)
	rs.stop_next_reel()
	rs.stop_next_reel()
	rs.stop_next_reel()
	_check(rs.is_absorbing(0) and rs.is_absorbing(1) and rs.is_absorbing(2), "三列同时进入吸附")
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped == [true, true, true], "三列全部落子")
	_check(finished[0] == 1, "全部吸附完成后只发一次 spin_finished")
	rs.spin_finished.disconnect(on_finished)

	# 6. 吸附不消耗全局 RNG
	# 2026-11-12：前面的用例会触发一次真实 spin_finished，可能的结算/敌人回合在 0.45s 窗口外
	# 才收尾（速度曲线变慢后时序改变）。先等后台流程静默，再开始 RNG 取样，避免把结算随机
	# 误记为吸附消耗。
	await get_tree().create_timer(0.6).timeout
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	# 只停第 1 列、保留另外两列未停：吸附完成时不会触发 finish_spin/结算，
	# 从而把观测窗口严格限定在吸附本身（避免把回合结算的随机误记为吸附消耗）。
	rs.reel_stopped.assign([false, false, false])
	rs._pending_stops.clear()
	_arm_reel(duel, 0, 0, 0.7)
	seed(777777)
	var expected: Array = []
	for _i in 16:
		expected.append(randi())
	seed(777777)
	rs.stop_next_reel()
	await get_tree().create_timer(0.45).timeout
	var after: Array = []
	for _i in 16:
		after.append(randi())
	_check(rs.reel_stopped[0], "RNG 用例中吸附完成")
	_check(expected == after, "停轮吸附不消耗全局 RNG（停列爆裂粒子也不得取全局随机）")
