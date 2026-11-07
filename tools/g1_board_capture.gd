extends Node

# ============================================================================
# G1 棋盘改版预览采集（2026-11-06）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g1_board_capture.tscn
# 产物：docs/baseline/2026-11-06_board/{01..06}_*.png + board_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-06_board"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G1 棋盘改版预览（2026-11-06）")
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

	# 整备页 → 开棋盘 → 确认开战
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)
	_dump_board()

	await _shot("01_board_full")

	# 02 岔路 A：n6 剩 2 步，上下两条中段高亮
	_rewind("n6", 2)
	await _shot("02_fork_a")

	# 03 岔路 B：n9 剩 1 步，两条尾路高亮
	_rewind("n9", 1)
	await _shot("03_fork_b")

	# 04 尾路 BOSS：n13 剩 1 步，BOSS 高亮
	_rewind("n13", 1)
	await _shot("04_boss_target")

	# 05 剩余步数：n1 胜利后剩 2 步，按钮为「继续」
	_rewind("n1", 2)
	await _shot("05_continue_steps")

	# 06 BOSS 悬停信息（节点名字 + 元素 + 机制）
	var scr = _duel.hud.board_screen
	scr._on_node_hover("n14")
	await _wait(0.2)
	await _shot("06_boss_info")

	# 07 战斗确认层：落到 BOSS 前先展示敌人与预览数值
	_rewind("n13", 1)
	scr._show_battle_confirm(_duel.board.node_by_id("n14"))
	await _wait(0.25)
	await _shot("07_battle_confirm")

	_write_log()
	print("G1_BOARD|DONE shots=%d" % _shots.size())
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
	_lines.append("## 棋盘拓扑")
	_lines.append("节点数=%d  路线长度=%d  战斗房=%d  BOSS=%s" % [
		b.node_count(), b.route_length(), b.battle_rooms.size(), ",".join(b.boss_ids)])
	for n in b.nodes:
		var room_name := "—"
		var room: RoomData = n.get("room")
		if room != null:
			room_name = "%s(%s)" % [room.name, room.kind]
		_lines.append("  %-4s %-7s depth=%-2d ria=%-2d next=%s room=%s" % [
			String(n["id"]), String(n["type"]), int(n["depth"]), int(n.get("ria", -1)),
			str(n.get("next", [])), room_name])
	_lines.append("")
	_lines.append("## 本局四人 BOSS 分配")
	for id in b.boss_ids:
		var bn: Dictionary = b.node_by_id(id)
		var r: RoomData = bn.get("room")
		_lines.append("  %s → %s" % [id, "缺失" if r == null else "%s（%s）" % [r.name, ElementCounter.label(r.element)]])
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
	var f := FileAccess.open("%s/board_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
