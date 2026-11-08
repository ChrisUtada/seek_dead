extends Node

# ============================================================================
# G4-01 分支价值模板预览采集（2026-11-08）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g4_template_capture.tscn
# 产物：docs/baseline/2026-11-08_g4_templates/{01..07}_*.png + template_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_g4_templates"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G4-01 分支价值模板预览（2026-11-08）")
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

	# 固定骨架与特殊格，只让模板变化，便于逐张比对。
	_duel.board_config.shape_id = "standard"
	_duel.board_config.special_id = "treasure"
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.8)

	var templates := ["standard", "mirror", "elite_first", "elite_upper", "elite_lower"]
	for tid in templates:
		_duel.board_config.template_id = String(tid)
		seed(20261108)
		_duel.board.generate(_duel.board_config)
		_rewind("n0", 0)
		await _wait_frames(3)
		await _shot("%02d_tpl_%s" % [templates.find(tid) + 1, String(tid)])
		_dump_template()

	# 非对称模板三档验收（480 原生 / 960 已采 / 1440）
	_duel.board_config.template_id = "elite_upper"
	seed(20261108)
	_duel.board.generate(_duel.board_config)
	_rewind("n0", 0)
	get_window().size = Vector2i(480, 270)
	await _wait_frames(4)
	await _shot("06_tpl_elite_upper_480")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("07_tpl_elite_upper_1440")
	get_window().size = Vector2i(960, 540)

	_write_log()
	print("G4_TEMPLATE|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _rewind(id: String, steps: int) -> void:
	_duel.board.consumed.clear()
	_duel.board.current_id = id
	_duel.board.consumed[id] = true
	_duel.board.dice = steps
	_duel.board.last_roll = 0
	_duel.board.feedback = ""
	_duel.hud.board_screen.show_board(_duel.board)
	_duel.hud.board_screen.refresh()


func _dump_template() -> void:
	var b = _duel.board
	_lines.append("## %s（骨架 %s）" % [String(b.template_id), String(b.shape_id)])
	var parts: Array[String] = []
	for id in ["n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9", "n10", "n11", "n12"]:
		parts.append("%s:%s" % [id, String(b.node_by_id(id).get("type", ""))])
	_lines.append("  " + "  ".join(parts))
	var battles := 0
	for n in b.nodes:
		if String(n["type"]) in ["normal", "elite", "boss"]:
			battles += 1
	_lines.append("  战斗节点=%d（含 4 BOSS）  商店=%s  休整=%s  武器格=%s  护符格=%s" % [
		battles, _type_of(b, "shop"), _type_of(b, "rest"),
		_id_of_type(b, "weapon"), _id_of_type(b, "charm")])
	_lines.append("")


func _type_of(b, type: String) -> String:
	var out: Array[String] = []
	for n in b.nodes:
		if String(n["type"]) == type:
			out.append(String(n["id"]))
	return ",".join(out)


func _id_of_type(b, type: String) -> String:
	for n in b.nodes:
		if String(n["type"]) == type:
			return String(n["id"])
	return "—"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/template_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
