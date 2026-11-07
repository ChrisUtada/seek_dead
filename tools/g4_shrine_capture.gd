extends Node

# ============================================================================
# G4-04 神龛特殊格预览采集（2026-11-07）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g4_shrine_capture.tscn
# 产物：docs/baseline/2026-11-07_g4_shrine/{01..06}_*.png + shrine_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-07_g4_shrine"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G4-04 神龛特殊格预览（2026-11-07）")
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

	# 固定标准骨架 + 神龛，便于逐张比对
	_duel.board_config.shape_id = "standard"
	_duel.board_config.special_id = "shrine"
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)
	_dump_board()

	await _shot("01_shrine_board")

	# 悬停：效果开局公开
	var scr = _duel.hud.board_screen
	var shrine_node: Dictionary = _shrine_node()
	scr._on_node_hover(String(shrine_node["id"]))
	await _wait(0.2)
	await _shot("02_shrine_info")

	# 落地：效果立即结算，棋盘回显提示
	_rewind("n13", 1)
	_duel.player_hp = 40
	_duel._board_shrine(shrine_node)
	await _wait(0.3)
	await _shot("03_shrine_landed")

	# 480 原生 / 1440 三档验收
	_rewind("n0", 0)
	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("04_shrine_480")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("05_shrine_1440")

	_write_log()
	print("G4_SHRINE|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _shrine_node() -> Dictionary:
	for n in _duel.board.nodes:
		if String(n["type"]) == "shrine":
			return n
	return {}


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
	_lines.append("骨架=%s  模板=%s  特殊格=%s  节点数=%d  路线长度=%d  战斗房=%d" % [
		b.shape_id, b.template_id, _duel.board_config.special_id,
		b.node_count(), b.route_length(), b.battle_rooms.size()])
	_lines.append("")
	_lines.append("## 全部节点")
	for n in b.nodes:
		_lines.append("  %-4s %-8s depth=%-2d row=%d next=%s title=%s" % [
			String(n["id"]), String(n["type"]), int(n["depth"]), int(n.get("row", -1)),
			str(n.get("next", [])), String(n.get("title", ""))])
	_lines.append("")
	_lines.append("## 神龛")
	var sn := _shrine_node()
	if sn.is_empty():
		_lines.append("  （未生成）")
	else:
		_lines.append("  节点=%s  深度=%d" % [String(sn["id"]), int(sn["depth"])])
		_lines.append("  效果=%s  数值=%s" % [String(sn.get("shrine_kind", "")), str(sn.get("shrine_value", -1))])
		_lines.append("  描述=%s" % String(sn.get("desc", "")))
	_lines.append("")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/shrine_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
