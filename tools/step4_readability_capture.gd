extends Node

# ============================================================================
# Step 4 · 多对策提示与结果反馈验收（2026-11-11）
# 运行（必须窗口模式，headless 无帧缓冲、截图为空）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/step4_readability_capture.tscn
# 产物：docs/baseline/2026-11-11_step4_readability/
#   01_burst_{480,960,1440}.png     爆发窗口：局势 + 多对策
#   02_recovery_{480,960,1440}.png  恢复窗口：熔铸间隙 + 多对策
#   03_feedback_{480,960,1440}.png  真实结算：护盾/破甲/恢复/核爆/充能爆发/总伤害
#   capture_data.txt                每个窗口下的文本、最小宽、与 SPIN 的重叠检查
# 只读战斗状态并调用现有结算/反馈函数；不写资源、不结算奖励。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-11_step4_readability"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BOSS := "res://resources/rooms/frozen_urn.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const BLOCK := "res://resources/symbols/block.tres"
const HEAL := "res://resources/symbols/heal.tres"
const SPECIAL := "res://resources/symbols/flame_special.tres"
const PIERCE := "res://resources/symbols/bolt_shot.tres"
const ACID := "res://resources/consumables/acid_solvent.tres"
const CLEANSE := "res://resources/consumables/cleanse_potion.tres"
const PURIFY := "res://resources/consumables/purify_potion.tres"
const HEAL_POTION := "res://resources/consumables/heal_potion.tres"
const SIZES := [Vector2i(480, 270), Vector2i(960, 540), Vector2i(1440, 810)]

var _duel: DuelController
var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# Seek Dead · Step 4 多对策提示与结果反馈验收")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
	_lines.append("# 逻辑分辨率固定 480×270（canvas_items 拉伸）；窗口只做整数放大。")
	_lines.append("")

	var scene: PackedScene = load(DUEL_SCENE)
	_duel = scene.instantiate() as DuelController
	add_child(_duel)
	await _wait(0.4)

	_set_window(Vector2i(960, 540))
	_duel.board_config.enabled = false
	_select_loadout()
	_duel._confirm_loadout()
	await _wait(0.5)
	_start_room(load(BOSS))
	await _wait(0.5)
	_set_band([FIRE_SLASH, BLOCK, HEAL, SPECIAL, PIERCE])
	_set_belt([ACID, CLEANSE, PURIFY, HEAL_POTION])
	_duel.readability.apply_preset("readable")
	_duel.enemy_intent = {}

	# 爆发窗口：首轮第 2 回合（Step 3 参数）；冻结已生效，多对策应包含破甲/穿透/清净等。
	var g = _duel.current_gimmick
	for i in 4:
		if g != null and String(g.rhythm_window(_duel)) == "爆发":
			break
		if g != null:
			g.on_turn_begin(_duel)
	_duel.enemy_intent = {}
	_duel.readability.update_turn_target()
	_duel.invalidate_state()
	_duel.hud._refresh_meta()
	for size in SIZES:
		_set_window(size)
		await _wait(0.35)
		_dump("爆发", size)
		await _shot("01_burst_%d" % size.x)

	# 恢复窗口：爆发后一回合，不叠甲/冻结。
	if g != null:
		g.on_turn_begin(_duel)
	_duel.enemy_intent = {}
	_duel.readability.update_turn_target()
	_duel.invalidate_state()
	_duel.hud._refresh_meta()
	for size in SIZES:
		_set_window(size)
		await _wait(0.35)
		_dump("恢复", size)
		await _shot("02_recovery_%d" % size.x)

	# 真实结算：三列火符号 → 同元素三连 + 克制核爆 + 破甲 + 充能爆发。
	# 敌人 HP 调高只为避免击杀中断取图，不改任何结算公式。
	_set_window(Vector2i(960, 540))
	_duel.enemy_hp_max = 1000
	_duel.enemy_hp = 1000
	_duel.enemy_armor = 53
	_duel.enemy_armor_max = 53
	_duel.enemy_status.clear()
	_duel.player_hp = _duel.player_hp_max
	_duel.charge_points = max(0, _duel.BALANCE.charge_max - 1)
	_duel._charge_elem_counts = {}
	# 当前战斗只有 1 行落子（DuelController.ROWS = 1），三列都摆成火斩 → 同元素三连。
	var fire_sym: SymbolData = load(FIRE_SLASH)
	for r in _duel.REELS:
		_duel.grid[r][0] = fire_sym
		_duel.grid_elem[r][0] = "fire"
		_duel.hud._refresh_cell(r, 0)
	await _duel.combat.evaluate()
	await _wait(0.3)
	for size in SIZES:
		_set_window(size)
		await _wait(0.35)
		_dump("结算反馈", size)
		await _shot("03_feedback_%d" % size.x)

	_write_log()
	print("STEP4_CAPTURE|DONE")
	get_tree().quit(0)


func _select_loadout() -> void:
	var out: Array[String] = []
	for w in ["fire_sword", "ice_staff"]:
		for p in _duel.WEAPON_POOL:
			if p.ends_with(w + ".tres"):
				out.append(p)
				break
	_duel.selected_loadout.assign(out)
	_duel.selected_consumables.clear()
	_duel.selected_charms.clear()
	_duel.selected_skills.clear()


func _start_room(room: RoomData) -> void:
	_duel.ROOMS.clear()
	_duel.ROOMS.append(room)
	_duel.start_room_data(room, 0, 0, false)
	_duel.enemy_intent = {}
	_duel.reel_system._timer.stop()


func _set_band(paths: Array) -> void:
	for r in _duel.REELS:
		_duel.reel_system.reel_strips[r] = []
		for p in paths:
			_duel.reel_system.reel_strips[r].append([load(String(p)), "none"])


func _set_belt(paths: Array) -> void:
	_duel.consumable_slots.clear()
	var i := 0
	for p in paths:
		var d = load(String(p))
		_duel.consumable_slots.append({"path": String(p), "item_id": String(d.item_id),
			"charges": int(d.charges), "uid": "s4_%d" % i})
		i += 1


func _dump(label: String, win: Vector2i) -> void:
	var hud = _duel.hud
	var rd = _duel.readability
	var hint: Label = hud.p1_target_label
	var fb: Label = hud.feedback_label
	var spin: Control = hud.get_node("Margin/Content/MainRow/CenterStage/ReelDock/SpinBar/SpinButton")
	var vp := get_viewport().get_visible_rect()
	var hint_rect := hint.get_global_rect()
	var fb_rect := fb.get_global_rect()
	var spin_rect := spin.get_global_rect()
	var font := fb.get_theme_font("font")
	var fs := fb.get_theme_font_size("font_size")
	var fb_w := font.get_string_size(String(fb.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 0.0
	var hfont := hint.get_theme_font("font")
	var hfs := hint.get_theme_font_size("font_size")
	var hint_w := hfont.get_string_size(String(hint.text), HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x if hfont != null else 0.0
	_lines.append("## %s · 窗口 %d×%d" % [label, win.x, win.y])
	_lines.append("视口逻辑尺寸=%d×%d；CenterStage 宽=%d；提示行宽=%d；反馈行宽=%d" % [
		int(vp.size.x), int(vp.size.y),
		int(hud.get_node("Margin/Content/MainRow/CenterStage").size.x),
		int(hint.size.x), int(fb.size.x)])
	_lines.append("局势：%s" % String(hint.text))
	_lines.append("对策数=%d；tooltip 行数=%d" % [rd.counters.size(), String(hint.tooltip_text).split("\n").size()])
	_lines.append("反馈：%s" % String(fb.text))
	_lines.append("提示文本宽=%.0f / 行宽=%d；反馈文本宽=%.0f / 行宽=%d；提示最小宽=%d；反馈最小宽=%d" % [
		hint_w, int(hint.size.x), fb_w, int(fb.size.x),
		int(hint.get_combined_minimum_size().x), int(fb.get_combined_minimum_size().x)])
	_lines.append("提示在视口内=%s；反馈在视口内=%s；提示压 SPIN=%s；反馈压 SPIN=%s" % [
		str(vp.encloses(hint_rect)), str(vp.encloses(fb_rect)),
		str(hint_rect.intersects(spin_rect)), str(fb_rect.intersects(spin_rect))])
	_lines.append("")


# 截图与写盘（与 ui_capture_step0 相同模式）
func _set_window(target: Vector2i) -> void:
	get_window().size = target


func _shot(name: String) -> void:
	if _duel != null and _duel.hud != null and _duel.hud.symbol_tooltip != null:
		_duel.hud.symbol_tooltip.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_lines.append("截图：%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open(OUT_DIR + "/capture_data.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
