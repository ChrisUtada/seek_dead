extends Node

# ============================================================================
# G6-04 图鉴详情预览采集（2026-11-07）
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/g6_codex_capture.tscn
# 产物：docs/baseline/2026-11-07_g6_codex/{01..03}_codex_*.png + codex_data.txt
#
# 原则：只截图与读数；不写资源文件。会写 lobby_data.json，跑前/跑后必须备份/还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-07_g6_codex"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(480, 270)
	_lines.append("# Seek Dead · G6-04 图鉴详情（2026-11-07）")
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

	var sample := _sample_weapon()
	var charm := _sample_charm()
	# 只在本进程内造统计（存档由外部备份/还原）。
	_duel._codex.note_equipped([sample], [charm])
	_duel._codex.note_used("res://resources/consumables/heal_potion.tres")
	_duel._meta_store.record_source(sample, {"act": 1, "mode": "board", "node_type": "weapon", "room": "断桥武器格"})
	_duel._meta_store.record_source(sample, {"act": 1, "mode": "linear", "room_kind": "boss", "room": "苦痛之王"})
	_duel.mastery.mastery.clear()
	_duel.mastery.imprints.clear()
	_duel.mastery.mastery[sample] = 7
	_duel.mastery.imprints[sample] = {"forge": 2, "tune": {}}
	for sw in (load(sample) as WeaponData).symbols:
		if sw != null and sw.symbol != null:
			_duel.mastery.imprints[sample]["tune"][String(sw.symbol.resource_path)] = 1
			break
	_duel._codex.record_run(_duel.mastery)

	var anvil = _duel.hud.anvil_screen
	anvil.show_screen()
	await _wait(0.3)
	anvil._toggle_codex()
	await _wait(0.3)
	anvil._codex_sel = sample
	anvil._refresh_codex_detail()
	await _wait(0.2)
	await _shot("01_codex_480")
	get_window().size = Vector2i(960, 540)
	await _wait_frames(4)
	await _shot("02_codex_960")
	get_window().size = Vector2i(1440, 810)
	await _wait_frames(4)
	await _shot("03_codex_1440")

	_lines.append("## 图鉴示例：%s" % _name_of(sample))
	for line in _duel._codex.detail_lines(sample):
		_lines.append(String(line))
	_lines.append("")
	_write_log()
	print("G6_CODEX|DONE shots=%d" % _shots.size())
	get_tree().quit(0)


func _sample_weapon() -> String:
	var owned: Array = _duel.meta.get("owned_weapons", [])
	for p in owned:
		if load(String(p)) is WeaponData:
			return String(p)
	return "res://resources/weapon_templates/fire_sword.tres"


func _sample_charm() -> String:
	var owned: Array = _duel.meta.get("owned_charms", [])
	for p in owned:
		if load(String(p)) is ItemData:
			return String(p)
	return "res://resources/charms/guard_charm.tres"


func _name_of(path: String) -> String:
	var res = load(path)
	if res is WeaponData:
		return String(res.weapon_name)
	if res is ItemData:
		return String(res.item_name)
	return path.get_file().get_basename()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append("%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/codex_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
