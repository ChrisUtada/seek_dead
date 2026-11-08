extends Node

# ============================================================================
# G7-A S3 每幕棋盘主题取证（2026-11-08）
# 目的：确认 ACT1/2/3 棋盘共用骨架、只换配色与幕名，且每幕 BOSS 房来自本幕。
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/g7_act_theme_probe.tscn
# 产物：docs/baseline/2026-11-08_act_theme/{act1,act2,act3}.png + probe_data.txt
# 会实例化 duel（可能写存档）：跑前把 APPDATA 指到临时目录。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_act_theme"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# 每幕棋盘主题取证 %s" % Time.get_datetime_string_from_system())
	get_window().size = Vector2i(960, 540)

	_duel = load(DUEL_SCENE).instantiate() as DuelController
	# 不开 demo_config：act_only 会把 ALL_ROOMS 收窄成 ACT1，第二/三幕棋盘就无房可分。
	add_child(_duel)
	await _wait_frames(8)
	await _wait(0.4)

	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)

	var cfg = _duel.board_config
	cfg.shape_id = "standard"
	cfg.special_id = "treasure"
	cfg.template_id = ""
	var themes: Array = []
	for act in [1, 2, 3]:
		cfg.act = act
		seed(7300 + act)
		if not _duel.board.generate(cfg):
			_lines.append("## act%d GENERATE_FAIL" % act)
			continue
		_duel.hud.board_screen.show_board(_duel.board)
		await _wait(0.6)
		var scr = _duel.hud.board_screen
		var th: Dictionary = scr._act_theme
		themes.append(th)
		_lines.append("\n## act%d" % act)
		_lines.append("title=%s  bg=%s  map=%s  grid=%s  node=%s" % [
			scr._title_label.text, th["bg"].to_html(false), th["map"].to_html(false),
			th["grid"].to_html(false), th["node"].to_html(false)])
		_lines.append("board.act=%d  act_label=%s  progress=%s" % [
			int(_duel.board.act), _duel.board.act_label(), _duel.board.progress_text()])
		var bosses: Array[String] = []
		for id in _duel.board.boss_ids:
			var n: Dictionary = _duel.board.node_by_id(id)
			var r: RoomData = n.get("room")
			bosses.append("%s:%s/%s" % [id, String(r.name) if r != null else "-",
				"FINAL" if (r != null and r.final_boss) else String(r.kind) if r != null else "-"])
		_lines.append("bosses=%s" % "，".join(bosses))
		await _shot("act%d" % act)

	# 三幕配色必须两两不同（只换配色，不改骨架）
	var distinct := true
	for i in range(themes.size()):
		for j in range(i + 1, themes.size()):
			if String(themes[i]["map"].to_html(false)) == String(themes[j]["map"].to_html(false)):
				distinct = false
	_lines.append("\n## distinct_map_colors=%s" % ("OK" if distinct else "SAME"))

	var f := FileAccess.open("%s/probe_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("ACT_THEME_PROBE|DONE lines=%d distinct=%s" % [_lines.size(), distinct])
	_duel.queue_free()
	await _wait_frames(4)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	_lines.append("shot %s %dx%d" % [name, img.get_width(), img.get_height()])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
