extends Node

# ============================================================================
# G6-05 横向铸式预览采集（2026-11-08）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g6_forge_capture.tscn
# 产物：docs/baseline/2026-11-08_g6_forge/{01..04}_forge_*.png + forge_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_g6_forge"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

const FIRE := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const AXE := "res://resources/weapon_templates/battle_axe.tres"
const ICE := "res://resources/weapon_templates/ice_staff.tres"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(480, 270)
	_lines.append("# Seek Dead · G6-05 横向铸式（2026-11-08）")
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
	_duel._confirm_loadout()
	await _wait(0.4)

	# 只在本进程内造熟练/选择（存档由外部备份/还原）。
	_duel.meta["owned_weapons"] = [FIRE, DAGGER, AXE, ICE]
	_duel.meta["codex"] = {}
	for p in [FIRE, DAGGER, AXE, ICE]:
		_duel.meta["codex"][p] = {"uses": 3, "best_rank": 2, "best_mastery": 3, "forge": 0, "tune": {}}
	_duel._codex = preload("res://scripts/systems/codex_system.gd").new(_duel)
	var fs = _duel._forge_styles
	fs.set_style(FIRE, "lie_ren")
	fs.set_style(DAGGER, "wen_shou")
	fs.set_style(AXE, "po_cheng")
	fs.set_style(ICE, "shuang_ming")

	# 第一组：火焰剑 + 霜晶法杖（展示烈刃 MISS 与霜鸣伤害格变化）。
	_equip([FIRE, ICE])
	_duel.hud._show_loadout_screen()
	await _wait(0.3)
	# 整备会自动预选技能；技能的 MISS 权重会掩盖 5%/8% 的命中差异。本轮只演示武器带子。
	_duel.selected_skills.clear()
	var ls = _duel.hud.loadout_screen
	await _wait_frames(4)
	await _shot("00_loadout_bar_480")
	ls._toggle_forge()
	await _wait(0.3)
	await _shot("01_forge_480_fire_ice")
	get_window().size = Vector2i(960, 540)
	await _wait_frames(4)
	await _shot("02_forge_960_fire_ice")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("03_forge_1440_fire_ice")

	# 同组滚动到底：战斧 / 霜晶法杖两段（霜鸣的带子差异在此可见）。
	get_window().size = Vector2i(960, 540)
	await _wait_frames(4)
	var scroll = ls._forge_box.get_parent() as ScrollContainer
	scroll.scroll_vertical = 10000
	await _wait_frames(4)
	await _shot("04_forge_960_fire_ice_bottom")

	# 第二组：匕首 + 战斧（展示稳手 MISS 减少与破城斧斩格变化）。
	_equip([DAGGER, AXE])
	ls._refresh_forge()
	scroll.scroll_vertical = 140
	await _wait_frames(4)
	await _shot("05_forge_960_dagger_axe")

	_write_data(fs)
	_write_log()
	print("G6_FORGE|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _equip(paths: Array) -> void:
	_duel.selected_loadout.clear()
	for p in paths:
		_duel.selected_loadout.append(String(p))


func _write_data(fs) -> void:
	_lines.append("## 首批 4 把代表武器")
	_lines.append("")
	var pairs := {
		FIRE: [FIRE, ICE],
		DAGGER: [DAGGER, AXE],
		AXE: [AXE],
		ICE: [ICE],
	}
	for p in fs.supported_paths():
		var path := String(p)
		var d: Dictionary = fs.style_def(path)
		var wd: WeaponData = load(path)
		var wname: String = wd.weapon_name if wd != null else path.get_file().get_basename()
		_lines.append("### %s · %s" % [wname, String(d["name"])])
		_lines.append("解锁：%s" % fs.unlock_text(path))
		_lines.append("优势：%s" % String(d["adv"]))
		_lines.append("代价：%s" % String(d["cost"]))
		_lines.append(fs.stat_line(path))
		var diff: Array = _diff_raw(pairs[path], path, d)
		_lines.append("带子（%s）：%s" % [_pair_names(pairs[path]), "；".join(diff) if not diff.is_empty() else "无格数变化"])
		_lines.append("")


func _diff_raw(loadout: Array, path: String, def: Dictionary) -> Array:
	return ReelPreview.diff_lines(loadout, loadout, [], [], [], {}, 0, false, 0, {}, {}, {}, {path: def})


func _pair_names(paths: Array) -> String:
	var names: Array[String] = []
	for p in paths:
		var wd: WeaponData = load(String(p))
		names.append(wd.weapon_name if wd != null else String(p))
	return " + ".join(names)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/forge_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
