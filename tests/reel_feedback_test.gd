extends Node

# ============================================================================
# 转轮手感优化 · Step 4 定向测试（2026-11-12）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/reel_feedback_test.tscn
#
# 覆盖（真实 DuelController / BattleHUD，只验证表现层）：
#   1. 停列短反馈：边框亮起 + 0.14s 缩放回正，结束后不残留
#   2. 停列反馈按结果着色：目标/锁轮金、MISS/注废红、夺轮灰
#   3. 停列反馈不占输入（边框 mouse_filter=IGNORE）
#   4. control 预设也保留停列确认（不改变 P1 的文本/预览/缓冲差异）
#   5. 回合反馈分级：爆发/三连金、破甲蓝、恢复绿、普通命中默认色
#   6. 连击 2–8 的缩放幅度递增并封顶（无音频资源时的可视「音调」）
#   7. 新一轮清空缩放与颜色，不残留、不阻塞
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
	print("REELFEEDBACK|RESULT %s (checks=%d fails=%d)" % [
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
		print("REELFEEDBACK|FAIL|" + msg)


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
	duel.growth.perk_ids.clear()
	duel.reel_system._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.player_frost = 0
	duel.frozen_cols.clear()


func _run() -> void:
	var duel: DuelController = await _boot()
	_setup(duel)
	var hud = duel.hud
	var rd = duel.readability

	# 1. 停列短反馈：边框亮起 → 缩放回正 → 淡出
	hud._pulse_stop_cell(0, "target")
	var flash: Panel = hud.cell_stop_flashes[0][0]
	var cell: Control = hud.cells[0][0]
	_check(flash.modulate.a > 0.99, "停列反馈：边框立即亮起")
	await get_tree().create_timer(0.07).timeout
	_check(cell.scale.x > 1.0, "停列反馈：中途有轻微缩放（实测 %.3f）" % cell.scale.x)
	await get_tree().create_timer(0.12).timeout
	_check(cell.scale.is_equal_approx(Vector2.ONE), "停列反馈：0.14s 后缩放回正")
	_check(flash.modulate.a < 0.05, "停列反馈：0.14s 后边框淡出")

	# 2. 结果着色
	var sb := flash.get_theme_stylebox("panel") as StyleBoxFlat
	hud._pulse_stop_cell(0, "target")
	_check(sb.border_color == Palette.ACCENT_GOLD, "目标停轮：金色边框")
	hud._pulse_stop_cell(0, "miss")
	_check(sb.border_color == Palette.POP_DAMAGE, "MISS 停轮：红色边框")
	hud._pulse_stop_cell(0, "forced")
	_check(sb.border_color == Palette.MUTED_DIM, "夺轮停轮：弱化灰色边框")
	hud._pulse_stop_cell(0, "normal")
	_check(sb.border_color == Palette.TITLE, "普通停轮：主文字色边框")

	# 3. 不占输入
	_check(flash.mouse_filter == Control.MOUSE_FILTER_IGNORE, "停列边框不拦截鼠标")
	_check(cell.mouse_filter != Control.MOUSE_FILTER_IGNORE, "格子本身的鼠标过滤未被改动")

	# 4. control 预设也保留停列确认（文本/预览/缓冲差异不变）
	rd.apply_preset("control")
	var fire = load(TARGET_PATH)
	hud._clear_stop_feedback()
	rd.on_stop(0, fire, "normal")
	_check(flash.modulate.a > 0.99, "control 预设也有停列短确认")
	_check(String(hud.p1_stop_labels[0].text) == "", "control 预设仍不显示停轮文本")

	# 5. 回合反馈分级
	var counts := {String(fire.resource_path): [fire, "fire", 3]}
	hud._show_turn_feedback(counts, 12)
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.TITLE, "普通命中：默认文字色")
	hud._show_turn_feedback(counts, 10, true)
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.ACCENT_GOLD, "三连：金色")
	hud._show_turn_feedback(counts, 10, false, false, -1, -1, 0, 0, 30, 0)
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.ACCENT_GOLD, "核爆：金色")
	hud._show_turn_feedback(counts, 10, false, false, -1, -1, 0, 8, 0, 0)
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.ARMOR, "破甲：护甲蓝")
	hud._show_turn_feedback({}, 0, false, false, -1, 5)
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.POP_HEAL, "恢复：治疗绿")

	# 6. 连击幅度递增并封顶：0.12s 脉冲在中点（约 0.06s）达到峰值，直接测缩放
	var key := String(fire.resource_path)
	var pop3: float = await _measure_peak(hud, counts)
	var pop8: float = await _measure_peak(hud, {key: [fire, "fire", 8]})
	var pop12: float = await _measure_peak(hud, {key: [fire, "fire", 12]})
	_check(pop8 > pop3 + 0.005, "连击越高，反馈脉冲越大（%.3f > %.3f）" % [pop8, pop3])
	_check(absf(pop8 - pop12) < 0.005, "连击脉冲在 8 连封顶（%.3f ≈ %.3f）" % [pop8, pop12])

	# 7. 新一轮清空颜色与缩放
	hud._clear_badges()
	hud._clear_stop_feedback()
	_check(hud.feedback_label.text == "", "清空后反馈文本为空")
	_check(hud.feedback_label.get_theme_color("font_color") == Palette.TITLE, "清空后颜色回到默认")
	_check(hud.feedback_label.scale.is_equal_approx(Vector2.ONE), "清空后缩放回正")


# 触发一次普通命中反馈，在 0.12s 脉冲中点读取实际缩放峰值。
# 普通命中基础脉冲 1.02，连击项 = 0.006 × (clamp(连击,0,8) - 1)。
func _measure_peak(hud, counts: Dictionary) -> float:
	hud._show_turn_feedback(counts, 10)
	await get_tree().create_timer(0.06).timeout
	var peak: float = hud.feedback_label.scale.x
	hud._clear_badges()
	return peak
