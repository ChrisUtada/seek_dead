extends Node

# ============================================================================
# G0-01 当前可交付基线采集（2026-11-06）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g0_baseline_capture.tscn
# 产物：docs/baseline/2026-11-06/{01..08}_*.png + baseline_data.txt
#
# 原则：
# - 运行时把 demo_config.enabled 置 true，使界面与「ACT1 Demo 导出包」一致（8 房 / 白名单）。
# - 只截图与读数；战斗/大厅状态由真实入口生成，不写资源文件。
# - 会写 lobby_data.json（本局元进度），跑测前后必须备份/还原存档。
# - 资源全量数量另按 ResourceScan 统计，不受 demo 白名单影响。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-06"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(960, 540)
	_lines.append("# Seek Dead · G0-01 当前可交付基线")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
	_lines.append("# 运行方式：编辑器/源码窗口模式，demo_config 运行时启用（对应 ACT1 Demo 导出包）")
	_lines.append("")

	var scene: PackedScene = load(DUEL_SCENE)
	if scene == null:
		push_error("无法加载 duel.tscn")
		get_tree().quit(2)
		return
	_duel = scene.instantiate() as DuelController
	_duel.demo_config.enabled = true   # 运行时启用，不写回 .tres
	add_child(_duel)
	await _wait_frames(8)
	await _wait(0.4)

	_dump_sources()
	_dump_demo()

	# 01 整备（含 M2 棋盘开关）
	await _shot("01_loadout")

	# 02 线性首房
	_duel._confirm_loadout()
	await _wait(0.9)
	_dump_linear_rooms()
	_dump_run("线性模式")
	await _shot("02_linear_battle")

	# 03 M1 战后成长三槽
	_duel.room_flow.begin_post_battle()
	await _wait(0.5)
	await _shot("03_post_battle_growth")
	_duel.room_flow.auto_pick_post_battle(["supply", "growth", "build"])
	await _wait(0.3)

	# 回整备 → 开棋盘
	_duel.room_flow.return_to_loadout()
	await _wait(0.4)
	if not _duel.board_config.is_active():
		_duel.hud.loadout_screen._toggle_board_mode()
	await _wait(0.2)
	_duel._confirm_loadout()
	await _wait(0.7)
	_dump_board()

	# 04 棋盘起点
	await _shot("04_board_start")

	# 05 掷骰后的合法落点（固定 dice=1，落点 n1）
	_duel.board.dice = 1
	_duel.board.last_roll = 1
	_duel.hud.board_screen.refresh()
	await _wait(0.25)
	await _shot("05_board_legal_targets")

	# 06 走子后（n1 已消耗，棋子移动）
	var node: Dictionary = _duel.board.advance_to("n1")
	_duel.hud.board_screen.refresh()
	await _wait(0.3)
	await _shot("06_board_after_move")

	# 07 从棋盘进入战斗（HUD 节点计数）
	if not node.is_empty():
		_duel._on_board_node_entered(node)
		await _wait(0.9)
		await _shot("07_board_battle")

	# 08 棋盘商店（复用现有货架）
	_duel.board.return_to_board()
	await _wait(0.3)
	_duel._board_shop()
	await _wait(0.5)
	await _shot("08_board_shop")

	_dump_meta_state()
	_write_log()
	print("G0_BASELINE|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 数据
# ---------------------------------------------------------------------------

func _dump_sources() -> void:
	var weapons: Array = ResourceScan.scan_paths("res://resources/weapon_templates/")
	var charms: Array = ResourceScan.scan_paths("res://resources/charms/")
	var consumables: Array = ResourceScan.scan_paths("res://resources/consumables/")
	var skills: Array = ResourceScan.scan_paths("res://resources/skills/")
	var rooms: Array = ResourceScan.scan_resources("res://resources/rooms/", "RoomData")
	var bosses := 0
	var acts := {}
	for r in rooms:
		if r.kind == "boss" or r.final_boss:
			bosses += 1
		var a := int(r.act)
		acts[a] = int(acts.get(a, 0)) + 1
	_lines.append("## 资源全量（源码，未过滤 demo 白名单）")
	_lines.append("房间合计=%d  其中 BOSS=%d  非 BOSS=%d" % [rooms.size(), bosses, rooms.size() - bosses])
	var keys: Array = acts.keys()
	keys.sort()
	for a in keys:
		_lines.append("  房间 act%d=%d" % [int(a), int(acts[a])])
	_lines.append("武器=%d  护符=%d  消耗品=%d  技能=%d" % [
		weapons.size(), charms.size(), consumables.size(), skills.size()])
	_lines.append("装备合计（武器+护符+消耗品+技能）=%d/200" % [
		weapons.size() + charms.size() + consumables.size() + skills.size()])
	_lines.append("")


func _dump_demo() -> void:
	_lines.append("## ACT1 Demo 白名单（运行时启用后）")
	_lines.append("demo_active=%s  act_only=%s  房间=%d  武器=%d  技能=%d  道具=%d" % [
		str(_duel.demo_active()), str(_duel.demo_config.act_only), _duel.ALL_ROOMS.size(),
		_duel.WEAPON_POOL.size(), _duel.SKILL_POOL.size(), _duel.ITEM_POOL.size()])
	_lines.append("")


func _dump_linear_rooms() -> void:
	_lines.append("## 线性 ACT1 房间序列（demo 过滤后，_build_run 产物）")
	for i in range(_duel.ROOMS.size()):
		var r: RoomData = _duel.ROOMS[i]
		_lines.append("R%02d %-6s %-18s elem=%-6s hp=%-4d atk=%-3d armor=%-2d role=%-8s final=%s" % [
			i + 1, r.kind, r.name, r.element, r.hp, r.atk, r.armor, r.boss_role, str(r.final_boss)])
	_lines.append("")


func _dump_run(label: String) -> void:
	_lines.append("## 本局（%s）" % label)
	_lines.append("node_mode=%s  房间数=%d  room_index=%d" % [
		str(_duel.node_mode), _duel.ROOMS.size(), _duel.room_index])
	_lines.append("武器：%s" % _names(_duel.selected_loadout, "weapon_name"))
	_lines.append("技能：%s" % _names(_duel.selected_skills, "skill_name"))
	_lines.append("护符：%s" % _names(_duel.selected_charms, "item_name"))
	_lines.append("消耗品：%s" % _names(_duel.selected_consumables, "item_name"))
	_lines.append("金币=%d  HP=%d/%d" % [_duel.gold, _duel.player_hp, _duel.player_hp_max])
	_lines.append("")


func _dump_board() -> void:
	_lines.append("## 棋盘（--board / 整备开关）")
	_lines.append("generated=%s  节点数=%d  当前=%s  BOSS=%s  战斗房=%d" % [
		str(_duel.board.generated), _duel.board.node_count(), _duel.board.current_id,
		",".join(_duel.board.boss_ids), _duel.board.battle_rooms.size()])
	for n in _duel.board.nodes:
		var room_name := "—"
		var room: RoomData = n.get("room")
		if room != null:
			room_name = "%s(%s)" % [room.name, room.kind]
		_lines.append("  %-4s %-7s depth=%-2d ria=%-2d next=%s room=%s" % [
			String(n["id"]), String(n["type"]), int(n["depth"]), int(n.get("ria", -1)),
			str(n.get("next", [])), room_name])
	_lines.append("")


func _dump_meta_state() -> void:
	_lines.append("## 关键平衡值（balance_config 实值）")
	for k in ["player_dmg_mult", "player_hp_base", "ante_act_step_atk", "ante_room_step_atk",
			"ante_act_step_hp", "ante_room_step_hp", "charge_max", "loadout_min", "anvil_roll_cost"]:
		_lines.append("%s = %s" % [k, str(_duel.BALANCE.get(k))])
	_lines.append("")
	_lines.append("## 截图")
	for s in _shots:
		_lines.append("  %s" % s)
	_lines.append("")


func _names(paths: Array, field: String) -> String:
	if paths.is_empty():
		return "（空）"
	var out: Array[String] = []
	for p in paths:
		var res: Resource = load(p)
		var n := String(res.get(field)) if res != null and res.get(field) != null else String(p)
		out.append("%s [%s]" % [n, String(p).get_file()])
	return "，".join(out)


# ---------------------------------------------------------------------------
# 截图与写盘
# ---------------------------------------------------------------------------

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/baseline_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
