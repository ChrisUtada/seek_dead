extends Node

# ============================================================================
# P1 · 目押可读性原型自检
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p1_readability_test.tscn
#
# 覆盖（不依赖真人操作）：
#   1. 预设表数值 / 切换 / F8 循环顺序
#   2. 默认目标 = 主武器权重最高的 damage 符号（fire_slash）
#   3. 视觉中心索引 center_index（_frac < 0.5 / >= 0.5）
#   4. next_symbols 预览序列
#   5. 视觉落点无缓冲：立即落到视觉中心
#   6. 视觉落点 + 缓冲：排队一拍后落到视觉中心，且只等一拍
#   7. 预览行显示 / 隐藏
#   8. 遥测：目标命中、缓冲次数、每局清零
# ============================================================================

const WEAPON_DIR := "res://resources/weapon_templates/"
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
	print("P1READ|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
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
		print("P1READ|FAIL|" + msg)


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
	# 让测试完全可控：停掉真实节拍器，转轮状态由用例直接摆位。
	duel.reel_system._timer.stop()


func _run() -> void:
	var duel: DuelController = await _boot()
	_setup(duel)
	var rd = duel.readability
	var rs = duel.reel_system
	var hud = duel.hud

	# 1. 预设表
	rd.apply_preset("control")
	_check(rd.min_wait == 0.06 and rd.preview_slots == 0 and not rd.visual_stop and not rd.buffer_enabled, "control 预设数值")
	rd.apply_preset("readable")
	_check(rd.min_wait == 0.085 and rd.accel == 0.0007, "readable 速度")
	_check(rd.preview_slots == 2 and rd.visual_stop and rd.buffer_enabled and rd.feedback_enabled, "readable 预览/落点/缓冲/反馈")
	_check(hud.p1_target_label != null and String(hud.p1_target_label.text).contains("readable"), "目标行显示预设")
	rd.apply_preset("control")
	rd.cycle_preset()
	_check(rd.preset == "readable", "F8 循环 control→readable")
	rd.cycle_preset()
	_check(rd.preset == "control", "F8 循环 readable→control")

	# 2. 默认目标
	_check(rd.target_symbol_path == TARGET_PATH, "默认目标为 fire_slash（实际 %s）" % rd.target_symbol_path)
	_check(rd.target_label() == "火斩", "目标显示名（实际 %s）" % rd.target_label())

	# 3. 视觉中心索引
	var sv = hud.cell_spin_views[0][0]
	sv.set_process(false)   # 测试期间冻结视觉推进，手动摆位
	rs.reel_cursor.assign([0, 0, 0])
	_check(int(hud.visual_center_index(0)) >= 0, "HUD 能取到视觉中心")
	rs.reel_strips[0] = [
		[load("res://resources/symbols/trash.tres"), "none"],
		[load(TARGET_PATH), "fire"],
		[load("res://resources/symbols/gold.tres"), "none"],
	]
	sv._active = true
	sv._index = 0
	sv._frac = 0.0
	_check(sv.center_index() == 0, "center_index frac=0")
	sv._frac = 0.49
	_check(sv.center_index() == 0, "center_index frac=0.49")
	sv._frac = 0.5
	_check(sv.center_index() == 1, "center_index frac=0.5")
	sv._frac = 0.9
	_check(sv.center_index() == 1, "center_index frac=0.9")

	# 3b. 真实节拍下视觉中心与逻辑游标不漂移超过 1 格
	rd.apply_preset("control")
	sv.set_process(true)
	rs.begin_spin()
	for i in 24:
		await get_tree().process_frame
	var ci: int = int(hud.visual_center_index(0))
	var cur: int = int(rs.reel_cursor[0]) % rs.reel_strips[0].size()
	var diff: int = absi(ci - cur)
	diff = mini(diff, rs.reel_strips[0].size() - diff)
	_check(ci >= 0 and diff <= 1, "真实节拍：视觉中心与逻辑游标相差 ≤1 格 (ci=%d cur=%d)" % [ci, cur])
	rs._timer.stop()
	rs._spinning = false
	sv._active = false

	# 4. 预览序列
	var nxt: Array = rs.next_symbols(0, 2, 0)
	_check(nxt.size() == 2 and nxt[0].resource_path == TARGET_PATH, "next_symbols 从 base 之后取 2 格")

	# 5. 视觉落点（无缓冲）：视觉中心在下一格时立即锁定该格
	rd.apply_preset("visual")
	hud._refresh_p1_ui()
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	sv._active = true
	sv._index = 0
	sv._frac = 0.7
	rs.stop_next_reel()
	_check(rs.reel_stopped[0], "visual 无缓冲：立即锁定")
	_check(duel.grid[0][0].resource_path == TARGET_PATH, "visual 无缓冲：落在视觉中心下一格")

	# 6. 视觉落点 + 缓冲 + 反馈：排队一拍后锁定
	rd.apply_preset("readable")
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	sv._active = true
	sv._index = 0
	sv._frac = 0.7
	var before_stop := int(duel._telemetry.stop_total)
	var before_buf := int(duel._telemetry.buffer_queues)
	rs.stop_next_reel()
	_check(not rs.reel_stopped[0] and rs.has_pending_stop(0), "buffer：先排队，不立即锁定")
	rs.on_spin_tick()
	_check(rs.reel_stopped[0], "buffer：下一拍锁定")
	_check(duel.grid[0][0].resource_path == TARGET_PATH, "buffer：下一拍落在视觉中心")
	_check(rs._pending_stops.is_empty(), "buffer：最多一拍，队列清空")
	_check(int(duel._telemetry.buffer_queues) == before_buf + 1, "遥测记录缓冲次数")
	_check(int(duel._telemetry.stop_total) == before_stop + 1, "遥测记录主动按停")
	_check(int(duel._telemetry.target_hits) >= 1, "遥测记录目标命中")
	_check(float(duel._telemetry.target_hit_rate()) > 0.0, "目标停中率 > 0")
	_check(String(hud.p1_stop_labels[0].text).contains("✓"), "停轮结果行显示目标命中")
	_check(duel._telemetry.stop_outcomes.has("target"), "遥测记录 target outcome")

	# 7. 预览行显示 / 隐藏
	rd.apply_preset("preview")
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_cursor.assign([0, 0, 0])
	rs.reel_stopped.assign([false, false, false])
	sv._active = true
	sv._index = 0
	sv._frac = 0.0
	hud._refresh_p1_previews()
	_check(hud.p1_preview_row.visible, "preview 预设：预览行可见")
	_check(hud.p1_preview_labels[0][0].visible, "preview 预设：首格预览可见")
	_check(String(hud.p1_preview_labels[0][0].text).contains("火斩"), "预览显示目标符号")
	duel.growth.perk_ids.append("insight")
	hud._refresh_p1_previews()
	_check(hud.p1_preview_labels[0][2].visible, "洞察在预览行额外 +1 格")
	duel.growth.perk_ids.erase("insight")
	hud._refresh_p1_previews()
	_check(not hud.p1_preview_labels[0][2].visible, "无洞察时预览行回到 2 格")
	rd.apply_preset("control")
	hud._refresh_p1_previews()
	_check(not hud.p1_preview_row.visible, "control 预设：预览行隐藏")

	# 8. 每局清零
	rd.target_hits = 9
	duel._telemetry.target_hits = 9
	duel._reset_run_state()
	_check(rd.target_hits == 0, "新局清零 readability 统计")
	_check(int(duel._telemetry.target_hits) == 0 and int(duel._telemetry.stop_total) == 0, "新局清零遥测统计")
	_check(duel._telemetry.target_symbol == TARGET_PATH, "新局重新声明目标")
	_check(hud.p1_target_label.text.contains("火斩"), "新局目标行刷新")

	duel.queue_free()
	await get_tree().process_frame
