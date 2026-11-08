extends Node

# ============================================================================
# G6-01 生涯成就面板预览采集（2026-11-07）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g6_career_capture.tscn
# 产物：docs/baseline/2026-11-07_g6_career/{01..04}_*.png + career_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-07_g6_career"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G6-01 生涯成就面板（2026-11-07）")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
	_lines.append("")

	var scene: PackedScene = load(DUEL_SCENE)
	if scene == null:
		push_error("无法加载 duel.tscn")
		get_tree().quit(2)
		return
	_duel = scene.instantiate() as DuelController
	add_child(_duel)
	await _wait_frames(8)
	await _wait(0.4)
	# G6-03：用固定棋盘骨架与特殊格，让局末总结展示真实棋盘路线（只影响本进程）。
	_duel.board_config.enabled = true
	_duel.board_config.shape_id = "standard"
	_duel.board_config.special_id = "treasure"
	# 先确认开战以构建本局 ROOMS（否则 room_index 无 BOSS 可指），再回整备截图。
	_duel._confirm_loadout()
	await _wait(0.4)

	# 只在本进程内造一个可展示的生涯状态（不写资源；存档由外部备份/还原）。
	var career = _duel._career
	career.record_boss("res://resources/rooms/a1_brute_none.tres")
	career.record_boss("res://resources/rooms/a1_bulwark_poison.tres")
	career.record_boss("res://resources/rooms/a1_striker_light.tres")
	career.record_boss("res://resources/rooms/a1_trickster_dark.tres")
	career.note_board_weapon()
	for i in range(_duel.ROOMS.size()):
		if _duel.ROOMS[i].kind == "boss":
			_duel.room_index = i
			_duel.current_room = _duel.ROOMS[i]
			break
	_duel.selected_loadout.clear()
	for want in ["fire_sword", "frost_blade"]:
		for p in _duel.WEAPON_POOL:
			if String(p).ends_with(want + ".tres"):
				_duel.selected_loadout.append(String(p))
				break
	_duel.peaceful_win = false
	career.on_boss_cleared()
	await _wait(0.2)
	_dump()

	var ls = _duel.hud.loadout_screen
	ls.show_screen()
	await _wait(0.3)
	ls._toggle_career()
	await _wait(0.3)
	await _shot("01_career_panel_960")

	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("02_career_panel_480")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("03_career_panel_1440")

	# 480 底栏（确认 4 个按钮不挤出屏幕）
	ls._career_panel.visible = false
	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("04_loadout_480")

	# 局末生涯反馈：先展示定向解锁三选一，选完再回铁砧点结算。
	get_window().size = Vector2i(960, 540)
	ls._career_panel.visible = false
	ls.hide_screen()   # 还原 HUD，否则 meta_screen 的父级仍隐藏
	await _wait(0.2)
	_duel.hud.meta_screen.show_choice()
	await _wait(0.3)
	await _shot("05_career_unlock")

	var cands: Array = _duel._career.roll_unlock_candidates(3)
	if not cands.is_empty():
		var pick := String(cands[0].get("path", ""))
		_duel._on_career_unlock_chosen(pick)
		_lines.append("")
		_lines.append("## 本次定向解锁选择")
		_lines.append("%s（%s）" % [String(cands[0].get("name", "")), pick])
		await _wait(0.2)
	# 生涯里程碑可能积攒多次机会：全部选完，再截原铁砧点结算。
	while _duel._career.has_unlock_charge():
		var more: Array = _duel._career.roll_unlock_candidates(3)
		if more.is_empty():
			break
		_duel._on_career_unlock_chosen(String(more[0].get("path", "")))
		await _wait(0.2)
	await _wait(0.3)
	await _shot("06_meta_after_unlock")

	_write_log()
	print("G6_CAREER|DONE shots=%d unlocked=%d" % [_shots.size(), career.unlocked_count()])
	get_tree().quit(0)


func _dump() -> void:
	_lines.append("## 生涯状态")
	_lines.append("解锁 %d / %d · 已击败 BOSS %d" % [
		_duel._career.unlocked_count(), _duel._career.total_count(), _duel._career.boss_count()])
	_lines.append("下一目标：%s" % _duel._career.next_goal_hint())
	_lines.append("定向解锁机会：%d" % _duel._career.unlock_charges())
	_lines.append("")
	_lines.append("## 局末路线总结（G6-03）")
	if _duel._run_summary != null:
		for line in _duel._run_summary.lines():
			_lines.append(String(line))
	_lines.append("")
	for e in _duel._career.entries():
		_lines.append("[%s] %s — %s" % [
			"✓" if bool(e.get("unlocked", false)) else " ", String(e.get("title", "")), String(e.get("desc", ""))])
	_lines.append("")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/career_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
