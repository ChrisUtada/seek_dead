extends SceneTree

# ============================================================================
# 转轮手感优化 · Step 1 定向测试（2026-11-12）
# 运行：Godot --headless --fixed-fps 60 --path <项目> --script res://tests/reel_clock_test.gd
#
# 覆盖（纯计算，不加载战斗场景、不改战斗数值）：
#   1. 配置 / 空带 / 起转 / 重复停轮拒绝
#   2. 连续位置 → 中心索引（0.5 分界）与下一格预览
#   3. 30/60/120fps 同一时刻的连续位置一致
#   4. 30/60/120fps 同一时刻请求停轮 → 预测落点、吸附时长、最终位置一致
#   5. 停轮去重、吸附完成后不再改结果
#   6. 冻结列 / 锁轮列 / 循环带 / 边界
#   7. 全程不消耗全局 RNG
# ============================================================================

# 用 preload 而非全局类名：本测试以 --script 运行，不依赖编辑器扫描生成的
# global_script_class_cache；新脚本首次加入仓库时也能直接跑。
const ReelClockScript = preload("res://scripts/battle/reel_clock.gd")

var _checks := 0
var _fails := 0


func _initialize() -> void:
	_test_configuration_and_empty()
	_test_center_and_preview()
	_test_position_frame_independence()
	_test_landing_frame_independence()
	_test_stop_dedupe_and_settle()
	_test_frozen_locked_and_wrap()
	_test_no_rng()
	print("---")
	print("REELCLOCK|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(1 if _fails > 0 else 0)


func _test_configuration_and_empty() -> void:
	var c := ReelClockScript.new()
	c.configure([10, 0, 7])
	_check(c.reel_count() == 3, "3 列已配置")
	_check(c.state_name(0) == "IDLE", "普通列初始 IDLE")
	_check(c.state_name(1) == "EMPTY", "空带列初始 EMPTY")
	_check(c.center_index(1) == -1, "空带列无中心")
	_check(c.predicted_landing(1) == -1, "空带列无预测落点")
	_check(c.request_stop(1).is_empty(), "空带列拒绝停轮请求")
	c.start()
	_check(c.is_spinning(0) and c.is_spinning(2), "可旋转列同时起转")
	_check(not c.is_spinning(1), "空带列不起转")
	c.advance(0.1)
	_check(is_equal_approx(c.position(1), 0.0), "空带列位置保持 0")
	_check(c.snapshot(0)["state"] == "SPINNING", "snapshot 暴露状态")


func _test_center_and_preview() -> void:
	var c := ReelClockScript.new()
	c.configure([10])
	c.start(0.0)
	_check(c.center_index(0) == 0, "position=0 → 中心 0")
	c.start(0.49)
	_check(c.center_index(0) == 0, "position=0.49 → 中心 0")
	c.start(0.5)
	_check(c.center_index(0) == 1, "position=0.5 → 中心 1（与 _frac>=0.5 同口径）")
	c.start(9.6)
	_check(c.center_index(0) == 0, "position=9.6 在 10 格带子上回绕到 0")
	c.start(7.0)
	_check(c.preview_indexes(0, 3) == [8, 9, 0], "预览从中心之后取 3 格并回绕")
	_check(ReelClockScript.index_for_position(3.49, 10) == 3, "静态 index_for_position 下界")
	_check(ReelClockScript.index_for_position(3.5, 10) == 4, "静态 index_for_position 上界")
	_check(ReelClockScript.landing_index_at(3.2, 1.0, 10) == 4, "静态 landing_index_at = round(pos+decel)")
	_check(ReelClockScript.landing_index_at(3.2, 1.0, 0) == -1, "静态 landing_index_at 空带返回 -1")


func _test_position_frame_independence() -> void:
	var samples := {}
	for fps in [30, 60, 120]:
		var c := ReelClockScript.new()
		c.configure([30, 30, 30], 9.0, 0.18)
		c.start()
		for _i in fps:
			c.advance(1.0 / float(fps))
		samples[fps] = [c.position(0), c.position(1), c.position(2), c.center_index(0)]
	var p30: Array = samples[30]
	var p60: Array = samples[60]
	var p120: Array = samples[120]
	for i in 3:
		_check(absf(float(p30[i]) - float(p60[i])) < 1e-6,
			"1.0s 时 30fps 与 60fps 位置一致（列 %d）" % i)
		_check(absf(float(p60[i]) - float(p120[i])) < 1e-6,
			"1.0s 时 60fps 与 120fps 位置一致（列 %d）" % i)
	# 9 格/秒、0.18s 二次加速：1.0s 的解析位置 = 9*(0.45*0.18 + 0.55*0.18/3) + 9*0.82
	_check(absf(float(p60[0]) - 8.406) < 1e-3, "1.0s 位置等于闭式积分值 8.406（实测 %.6f）" % float(p60[0]))
	_check(int(p30[3]) == int(p60[3]) and int(p60[3]) == int(p120[3]), "1.0s 时三档帧率中心索引一致")


func _test_landing_frame_independence() -> void:
	var landings: Array = []
	var durations: Array = []
	var positions: Array = []
	for fps in [30, 60, 120]:
		var c := ReelClockScript.new()
		c.configure([30, 30, 30], 9.0, 0.18, 1.0)
		c.start()
		for _i in int(fps * 0.5):
			c.advance(1.0 / float(fps))
		var req: Dictionary = c.request_stop(0)
		_check(not req.is_empty(), "%dfps 请求停轮成功" % fps)
		_check(int(req["landing_index"]) == ReelClockScript.landing_index_at(
			float(req["from_position"]), float(req["decel_cells"]), 30),
			"%dfps 预测落点与静态公式一致" % fps)
		_check(float(req["stop_seconds"]) >= ReelClockScript.MIN_STOP_SECONDS
			and float(req["stop_seconds"]) <= ReelClockScript.MAX_STOP_SECONDS,
			"%dfps 减速吸附时长在 %.2f–%.2fs 区间" % [
				fps, ReelClockScript.MIN_STOP_SECONDS, ReelClockScript.MAX_STOP_SECONDS])
		landings.append(int(req["landing_index"]))
		durations.append(float(req["stop_seconds"]))
		positions.append(float(req["from_position"]))
		var elapsed := 0.0
		var landed: Array = []
		while landed.is_empty() and elapsed < 2.0:
			landed = c.advance(1.0 / float(fps))
			elapsed += 1.0 / float(fps)
		_check(landed == [0], "%dfps 吸附完成时报告一次落地" % fps)
		_check(c.state_name(0) == "STOPPED", "%dfps 吸附后状态 STOPPED" % fps)
		_check(c.center_index(0) == int(req["landing_index"]),
			"%dfps 停稳后视觉中心 = 预测落点" % fps)
		_check(is_equal_approx(c.position(0), float(req["landing_position"])),
			"%dfps 停稳后连续位置 = 记录的落点位置" % fps)
	_check(landings[0] == landings[1] and landings[1] == landings[2],
		"30/60/120fps 同一时刻停轮 → 同一落点（%s）" % [landings])
	_check(absf(float(durations[0]) - float(durations[1])) < 1e-9
		and absf(float(durations[1]) - float(durations[2])) < 1e-9,
		"30/60/120fps 吸附时长一致")
	_check(absf(float(positions[0]) - float(positions[1])) < 1e-6
		and absf(float(positions[1]) - float(positions[2])) < 1e-6,
		"30/60/120fps 请求瞬间位置一致")


func _test_stop_dedupe_and_settle() -> void:
	var c := ReelClockScript.new()
	c.configure([12])
	_check(c.request_stop(0).is_empty(), "未起转时拒绝停轮")
	c.start()
	c.advance(0.3)
	var first: Dictionary = c.request_stop(0)
	var second: Dictionary = c.request_stop(0)
	_check(not first.is_empty(), "首次停轮请求被接受")
	_check(second.is_empty(), "停止中重复停轮被拒绝")
	_check(c.is_stopping(0), "状态进入 STOPPING")
	var landed: Array = c.advance(c.stop_seconds(0))
	_check(landed == [0], "吸附完成报告落地一次")
	_check(c.state_name(0) == "STOPPED", "落地后 STOPPED")
	_check(is_equal_approx(c.position(0), float(first["landing_position"])),
		"落地位置等于请求时预测的落点")
	var before: float = c.position(0)
	var again: Array = c.advance(0.5)
	_check(again.is_empty(), "落地后不再报告落地")
	_check(is_equal_approx(c.position(0), before), "落地后结果不再被修改")
	_check(c.request_stop(0).is_empty(), "已停止列拒绝再次停轮")

	# 大步长：一次 delta 超过吸附时长，仍停在同一个预测落点。
	var big := ReelClockScript.new()
	big.configure([12])
	big.start()
	big.advance(0.25)
	var req := big.request_stop(0)
	var landed_big: Array = big.advance(5.0)
	_check(landed_big == [0], "大 delta 也能完成吸附")
	_check(is_equal_approx(big.position(0), float(req["landing_position"])),
		"大 delta 落点与请求时预测一致")


func _test_frozen_locked_and_wrap() -> void:
	var c := ReelClockScript.new()
	c.configure([12, 12, 12])
	c.start()
	c.advance(0.2)
	var p1: float = c.position(1)
	var p2: float = c.position(2)
	c.mark_frozen(1)
	c.mark_locked(2)
	_check(c.state_name(1) == "FROZEN", "冻结列状态")
	_check(c.state_name(2) == "LOCKED", "锁轮列状态")
	_check(c.request_stop(1).is_empty() and c.request_stop(2).is_empty(), "冻结/锁轮列拒绝停轮")
	_check(c.center_index(1) == -1 and c.predicted_landing(2) == -1, "冻结/锁轮列无中心与落点")
	c.advance(0.4)
	_check(is_equal_approx(c.position(1), p1) and is_equal_approx(c.position(2), p2),
		"冻结/锁轮列不推进位置")
	_check(c.is_spinning(0), "冻结/锁轮不影响其它列")

	# 循环带与边界：长距离推进后位置始终落在 [0, n)。
	var loop := ReelClockScript.new()
	loop.configure([7], 12.0, 0.1)
	loop.start()
	for _i in 200:
		loop.advance(1.0 / 30.0)
	_check(loop.position(0) >= 0.0 and loop.position(0) < 7.0, "循环带位置始终在 [0, 7)")
	_check(loop.center_index(0) >= 0 and loop.center_index(0) < 7, "循环带中心索引合法")

	# 重新起转/重置清掉停轮状态。
	loop.reset()
	_check(loop.state_name(0) == "IDLE", "reset 回到 IDLE")
	_check(is_equal_approx(loop.position(0), 0.0), "reset 清零位置")
	_check(loop.stop_seconds(0) == 0.0, "reset 清零吸附时长")


func _test_no_rng() -> void:
	seed(424242)
	var expected: Array = []
	for _i in 64:
		expected.append(randi())
	seed(424242)
	var c := ReelClockScript.new()
	c.configure([30, 30, 30])
	c.start()
	for _i in 500:
		c.advance(1.0 / 60.0)
	c.request_stop(0)
	c.request_stop(1)
	c.advance(1.0)
	c.request_stop(2)
	c.advance(0.2)
	c.reset()
	c.start(3.5)
	c.advance(0.5)
	var after: Array = []
	for _i in 64:
		after.append(randi())
	_check(expected == after, "连续时间/落点计算不消耗全局 RNG")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		return
	_fails += 1
	printerr("FAIL: " + label)
