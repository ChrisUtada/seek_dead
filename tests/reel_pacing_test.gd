extends Node

# ============================================================================
# 转轮手感优化 · Step 3 定向测试（2026-11-12）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reel_pacing_test.tscn
#
# 覆盖（真实 DuelController，冻结节拍器后手动驱动 on_spin_tick）：
#   1. 巡航/封顶与 ReadabilitySystem 的缩放后常量一致（2026-11-12：5.7 / 7.6 格/秒）
#   2. 加速段逐步逼近封顶，且永不超过封顶
#   3. 手动按停立即响应（不额外加延迟）
#   4. 自动/夺轮停列按 0.25s + 0.07s 递增的逐列节奏，而不是同一拍全部停下
#   5. 完整旋转模型耗时被记录，且没有无意义等待
#   6. 手动与自动停轮落点算法一致
#   7. 加速与自动停轮节奏不消耗全局 RNG
# ============================================================================

const TARGET_PATH := "res://resources/symbols/fire_slash.tres"
# 2026-11-12：符号 32px、槽距 30px 后，速度曲线按 19/30 等比缩放；断言跟随常量，避免再次漂移。
const ReadabilityScript := preload("res://scripts/systems/readability_system.gd")

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
	print("REELPACE|RESULT %s (checks=%d fails=%d)" % [
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
		print("REELPACE|FAIL|" + msg)


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
	duel.growth.perk_ids.clear()          # 排除「稳定节奏」对基础间隔的影响
	duel.readability.apply_preset("control")
	duel.reel_system._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.player_frost = 0
	duel.frozen_cols.clear()


func _stack_strips(duel: DuelController) -> void:
	var one := [[duel.TRASH_SYMBOL, "none"], [load(TARGET_PATH), "fire"], [duel.GOLD_SYMBOL, "none"]]
	duel.reel_system.reel_strips = [one.duplicate(true), one.duplicate(true), one.duplicate(true)]


# 起转并冻结节拍器；stopped 指定各列是否已停。
func _start(duel: DuelController, stopped: Array, cursor: int = 0) -> void:
	var rs = duel.reel_system
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([cursor, cursor, cursor])
	rs.reel_stopped.assign(stopped)
	rs._pending_stops.clear()


func _run() -> void:
	var duel: DuelController = await _boot()
	_setup(duel)
	_stack_strips(duel)
	var rs = duel.reel_system

	# 1. 速度区间：起转初速 5 CPS，巡航/封顶跟随 ReadabilitySystem（缩放后 5.7 / 7.6 格/秒）
	_start(duel, [false, true, true])
	var start_cps: float = 1.0 / rs.current_spin_wait()
	_check(start_cps >= 4.5 and start_cps <= 5.5, "起转初速在 4.5–5.5 格/秒（实测 %.2f）" % start_cps)
	var cruise_cps: float = 1.0 / rs._base_wait()
	_check(is_equal_approx(cruise_cps, ReadabilityScript.CRUISE_CPS),
		"巡航速度 = ReadabilitySystem.CRUISE_CPS（实测 %.2f / %.2f）" % [cruise_cps, ReadabilityScript.CRUISE_CPS])
	var cap_cps: float = 1.0 / float(rs._min_wait())
	_check(is_equal_approx(cap_cps, ReadabilityScript.MAX_CPS),
		"高速封顶 = ReadabilitySystem.MAX_CPS（实测 %.2f / %.2f）" % [cap_cps, ReadabilityScript.MAX_CPS])
	_check(rs.STARTUP_RAMP_SECONDS >= 0.28 and rs.STARTUP_RAMP_SECONDS <= 0.35,
		"启动加速段在 0.28–0.35s（实测 %.2f）" % rs.STARTUP_RAMP_SECONDS)
	_check(rs.auto_stop_interval(0) >= 0.22 and rs.auto_stop_interval(0) <= 0.28,
		"逐列基础停顿在 0.22–0.28s（实测 %.2f）" % rs.auto_stop_interval(0))
	var step: float = rs.auto_stop_interval(1) - rs.auto_stop_interval(0)
	_check(step >= 0.06 and step <= 0.08, "后续列递增在 0.06–0.08s（实测 %.2f）" % step)

	# 2. 启动段平滑接近巡航；随后逐步逼近封顶，且永不超过封顶
	var saw_max := false
	var over_cap := false
	var startup_monotonic := true
	var previous_cps := start_cps
	var reached_cruise_at := -1.0
	var cruise_after_startup := 0.0
	for _i in 40:
		rs.on_spin_tick()
		var w: float = rs.current_spin_wait()
		var cps: float = 1.0 / w
		if rs.spin_model_seconds() <= rs.STARTUP_RAMP_SECONDS + 0.001:
			startup_monotonic = startup_monotonic and cps + 0.001 >= previous_cps
			previous_cps = cps
		if reached_cruise_at < 0.0 and rs.spin_model_seconds() >= rs.STARTUP_RAMP_SECONDS:
			reached_cruise_at = rs.spin_model_seconds()
			cruise_after_startup = cps
		if cps > cap_cps + 0.001:
			over_cap = true
		if is_equal_approx(w, rs._min_wait()):
			saw_max = true
	_check(startup_monotonic, "启动段速度单调上升，没有先跳高速再回落")
	_check(reached_cruise_at >= 0.28 and reached_cruise_at <= 0.45,
		"启动段按节拍量化后约 0.32s 结束（实测 %.3fs）" % reached_cruise_at)
	_check(absf(cruise_after_startup - cruise_cps) <= 0.01,
		"启动段结束接入 %.1f 格/秒巡航，不提前逐拍加速（实测 %.2f）" % [cruise_cps, cruise_after_startup])
	_check(not over_cap, "加速段从未超过 %.1f 格/秒封顶" % cap_cps)
	_check(saw_max, "持续旋转后到达封顶速度")
	_check(rs.spin_model_seconds() > 0.0, "旋转模型耗时在累积")

	# 2b. 真实帧驱动：启动速度必须逐帧更新，而不是每格才跳一个档位
	_start(duel, [false, true, true])
	rs._timer.start()
	var frame_cps: Array[float] = []
	var frame_monotonic := true
	var previous_frame_cps := start_cps
	for _i in 18:
		await get_tree().process_frame
		var cps: float = 1.0 / rs.current_spin_wait()
		frame_cps.append(cps)
		frame_monotonic = frame_monotonic and cps + 0.001 >= previous_frame_cps
		previous_frame_cps = cps
	rs._timer.stop()
	var distinct_speeds := {}
	for cps in frame_cps:
		distinct_speeds[snappedf(cps, 0.0001)] = true
	_check(distinct_speeds.size() >= 12,
		"0.3s 内至少出现 12 个连续速度采样（实测 %d）" % distinct_speeds.size())
	_check(frame_monotonic, "逐帧启动速度单调上升，没有回落或跳档")
	# 缩放后起转初速 5.0 → 巡航 5.7，0.3s 内应接近巡航但不超过它。
	_check(not frame_cps.is_empty() and frame_cps[-1] > start_cps + 0.3
		and frame_cps[-1] <= cruise_cps + 0.01,
		"真实帧驱动在启动段内平滑接近巡航")

	# 3. 手动按停立即进入吸附（不额外等待逐列停顿）
	_start(duel, [false, true, true])
	rs.lock_reel(0, false, "player")
	_check(rs.is_absorbing(0), "手动按停立即进入吸附")

	# 4. 自动夺轮：按 0.25s / +0.07s 的逐列节奏停下
	_start(duel, [false, false, false])
	duel.pending_auto_stop = true
	var stop_times: Array = []
	var sim := 0.0
	for _i in 400:
		rs._timer.wait_time = 0.05   # 统一 20 帧/秒的模拟节拍，便于核对间隔
		rs.on_spin_tick()
		sim += 0.05
		var absorbing := 0
		for r in 3:
			if rs.is_absorbing(r):
				absorbing += 1
		while stop_times.size() < absorbing:
			stop_times.append(sim)
		if stop_times.size() >= 3:
			break
	_check(stop_times.size() == 3, "自动停轮依次停下三列")
	if stop_times.size() == 3:
		var t1: float = float(stop_times[0])
		var t2: float = float(stop_times[1])
		var t3: float = float(stop_times[2])
		_check(absf(t1 - 0.25) <= 0.051, "第 1 列在约 0.25s 停下（实测 %.2f）" % t1)
		_check(absf((t2 - t1) - 0.32) <= 0.051, "第 2 列间隔约 0.32s（实测 %.2f）" % (t2 - t1))
		_check(absf((t3 - t2) - 0.39) <= 0.051, "第 3 列间隔约 0.39s（实测 %.2f）" % (t3 - t2))
		_check(t1 < t2 and t2 < t3, "逐列停轮时间严格递增")
	duel.pending_auto_stop = false

	# 5. 完整旋转耗时：几拍旋转 + 三列吸附完成后记录，且没有无意义等待
	_start(duel, [false, false, false])
	for _i in 5:
		rs._timer.wait_time = 0.1
		rs.on_spin_tick()
	var before_finish: float = rs.spin_model_seconds()
	rs.stop_next_reel()
	rs.stop_next_reel()
	rs.stop_next_reel()
	await get_tree().create_timer(0.35).timeout
	_check(rs.reel_stopped == [true, true, true], "三列吸附完成")
	var total: float = rs.last_spin_seconds()
	_check(total >= before_finish, "完整旋转耗时包含前半段旋转（%.2f ≥ %.2f）" % [total, before_finish])
	_check(total > 0.4 and total < 3.0, "完整旋转耗时有记录且不拖沓（实测 %.2fs）" % total)

	# 6. 手动与自动停轮落点算法一致（同一游标/同一带子）
	_start(duel, [false, true, true], 1)
	rs.lock_reel(0, false, "player")
	var manual_landing: int = rs.absorb_target(0)
	_start(duel, [false, true, true], 1)
	rs.stop_next_reel(false, "forced")
	var auto_landing: int = rs.absorb_target(0)
	_check(manual_landing == auto_landing, "手动/自动停轮落点一致（%d/%d）" % [manual_landing, auto_landing])

	# 7. 加速与自动停轮节奏不消耗 RNG
	_start(duel, [false, false, false])
	duel.pending_auto_stop = true
	seed(919191)
	var expected: Array = []
	for _i in 16:
		expected.append(randi())
	seed(919191)
	for _i in 30:
		rs._timer.wait_time = 0.05
		rs.on_spin_tick()
	var after: Array = []
	for _i in 16:
		after.append(randi())
	_check(expected == after, "加速/自动停轮不消耗全局 RNG")
