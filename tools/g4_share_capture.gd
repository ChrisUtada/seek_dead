extends Node

# ============================================================================
# G4-02 第三套骨架（long_share）预览采集（2026-11-08）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g4_share_capture.tscn
# 产物：docs/baseline/2026-11-08_g4_share/{01..06}_*.png + share_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_g4_share"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G4-02 延展共享段骨架预览（2026-11-08）")
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

	# 固定延展共享段骨架 + 宝箱 + 标准模板，便于逐张比对
	_duel.board_config.shape_id = "long_share"
	_duel.board_config.special_id = "treasure"
	_duel.board_config.template_id = "standard"
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)
	_dump_board()

	_rewind("n0", 0)
	await _shot("01_share_full")

	# 共享段商店 n29（武器 → 护符之间多出的消费点）
	_rewind("n5", 1)
	_duel.hud.board_screen._on_node_hover("n29")
	await _wait(0.2)
	await _shot("02_share_shop")

	# 岔路 A：整体后移 1 格，两侧 BOSS 信息仍可见
	_rewind("n6", 0)
	_duel.hud.board_screen._on_node_hover("n6")
	await _wait(0.2)
	await _shot("03_share_fork")

	# 三档验收
	_rewind("n0", 0)
	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("04_share_480")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("05_share_1440")
	get_window().size = Vector2i(960, 540)

	# 武器格 tooltip：替换影响（G4-03 收口）
	var wn: Dictionary = _node_of_type("weapon")
	if not wn.is_empty():
		_lines.append("## 武器格 tooltip（替换影响）")
		_lines.append(_duel.hud.board_screen._tooltip(wn))
		_lines.append("")
		_lines.append("## 精英节点 desc（奖励方向）")
		for n in _duel.board.nodes:
			if String(n["type"]) == "elite":
				_lines.append(String(n.get("desc", "")))
				break
		_lines.append("")

	_write_log()
	print("G4_SHARE|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _node_of_type(type: String) -> Dictionary:
	for n in _duel.board.nodes:
		if String(n["type"]) == type:
			return n
	return {}


func _rewind(id: String, steps: int) -> void:
	_duel.board.consumed.clear()
	_duel.board.current_id = id
	_duel.board.consumed[id] = true
	_duel.board.dice = steps
	_duel.board.last_roll = 0
	_duel.board.feedback = ""
	_duel.hud.board_screen.show_board(_duel.board)
	_duel.hud.board_screen.refresh()


func _dump_board() -> void:
	var b = _duel.board
	_lines.append("## 骨架")
	_lines.append("骨架=%s  模板=%s  节点数=%d  路线长度=%d  战斗房=%d" % [
		b.shape_id, b.template_id, b.node_count(), b.route_length(), b.battle_rooms.size()])
	_lines.append("")
	for n in b.nodes:
		var room_name := "—"
		var room: RoomData = n.get("room")
		if room != null:
			room_name = "%s(%s)" % [room.name, room.kind]
		_lines.append("  %-4s %-8s depth=%-2d row=%d ria=%-2d next=%s room=%s" % [
			String(n["id"]), String(n["type"]), int(n["depth"]), int(n.get("row", -1)),
			int(n.get("ria", -1)), str(n.get("next", [])), room_name])
	_lines.append("")
	_lines.append("## 四条尾路")
	for t in [["n13", "n21", "n14"], ["n15", "n22", "n16"],
			["n17", "n23", "n18"], ["n19", "n24", "n20"]]:
		var parts: Array[String] = []
		for id in t:
			parts.append("%s:%s" % [id, String(b.node_by_id(String(id)).get("type", ""))])
		_lines.append("  " + " → ".join(parts))
	_lines.append("")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/share_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
