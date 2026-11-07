extends Node

# ============================================================================
# G4 主题分布预览采集（2026-11-07）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g4_theme_capture.tscn
# 产物：docs/baseline/2026-11-07_g4_theme/{01..05}_*.png + theme_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-07_g4_theme"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const NODE = preload("res://scripts/board/board_node_data.gd")

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G4 主题分布预览（2026-11-07）")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
	_lines.append("")

	var scene: PackedScene = load(DUEL_SCENE)
	if scene == null:
		push_error("无法加载 duel.tscn")
		get_tree().quit(2)
		return
	_duel = scene.instantiate() as DuelController
	_duel.demo_config.enabled = true
	add_child(_duel)
	await _wait_frames(8)
	await _wait(0.4)

	# 固定标准骨架 + 宝箱，便于逐张比对（主题本身与特殊格无关）
	_duel.board_config.shape_id = "standard"
	_duel.board_config.special_id = "treasure"
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)
	_dump_board()

	await _shot("01_theme_board")

	# 尾路首战：主题与 BOSS 同系（挑一条非特殊格的尾路）
	var scr = _duel.hud.board_screen
	for id in ["n13", "n15", "n17", "n19"]:
		var n: Dictionary = _duel.board.node_by_id(String(id))
		if NODE.is_battle(String(n["type"])):
			scr._on_node_hover(String(id))
			await _wait(0.2)
			await _shot("02_theme_tail_info")
			break

	# 尾路岔路：两条尾路的 BOSS 名字 + 元素（风险提示）
	scr._on_node_hover("n12")
	await _wait(0.2)
	await _shot("03_theme_fork")

	# 480 原生 / 1440 三档验收
	_rewind("n0", 0)
	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("04_theme_480")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("05_theme_1440")

	_write_log()
	print("G4_THEME|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _rewind(id: String, steps: int) -> void:
	_duel.board.consumed.clear()
	_duel.board.current_id = id
	_duel.board.consumed[id] = true
	_duel.board.dice = steps
	_duel.board.feedback = ""
	_duel.hud.board_screen.show_board(_duel.board)
	_duel.hud.board_screen.refresh()


func _dump_board() -> void:
	var b = _duel.board
	_lines.append("## 骨架")
	_lines.append("骨架=%s  模板=%s  特殊格=%s  节点数=%d  路线长度=%d" % [
		b.shape_id, b.template_id, _duel.board_config.special_id,
		b.node_count(), b.route_length()])
	_lines.append("")
	_lines.append("## 尾路主题（首战 ← BOSS）")
	for pair in [["n13", "n14"], ["n15", "n16"], ["n17", "n18"], ["n19", "n20"]]:
		var head: Dictionary = b.node_by_id(String(pair[0]))
		var boss: Dictionary = b.node_by_id(String(pair[1]))
		var br: RoomData = boss.get("room")
		var hr: RoomData = head.get("room")
		_lines.append("  %s(%s) ← %s(%s)  主题=%s  首战元素=%s" % [
			String(pair[0]), String(head["type"]),
			String(boss["id"]), br.name if br != null else "缺失",
			ElementCounter.label(String(head.get("theme", ""))),
			ElementCounter.label(String(hr.element)) if hr != null else "（特殊格）"])
	_lines.append("")
	_lines.append("## 共享段 / 中段元素")
	for id in ["n1", "n3", "n4", "n6", "n7", "n8", "n10", "n11"]:
		var n: Dictionary = b.node_by_id(id)
		var r: RoomData = n.get("room")
		_lines.append("  %-4s %-6s %s" % [id, String(n["type"]),
			"%s（%s）" % [r.name, ElementCounter.label(r.element)] if r != null else "（空）"])
	_lines.append("")
	_lines.append("## 岔路提示")
	for id in ["n6", "n9", "n12"]:
		_lines.append("  %s: %s" % [id, String(b.node_by_id(id).get("desc", "")).replace("\n", " / ")])
	_lines.append("")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/theme_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
