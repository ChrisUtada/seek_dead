extends Node

# ============================================================================
# G0-02 布局实机采集（2026-11-06）
# 在 480×270 / 960×540 / 1440×810 三档窗口下截取：
#   整备 / 战斗（长 HP·Lv）/ 战后三槽 / 替换弹层 / 转轮预览（洞察 + P1 预览行）
# 运行（必须窗口模式）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/g0_ui_capture.tscn
# 产物：docs/baseline/2026-11-06_ui/{W}x{H}_{n}_{name}.png
# 会写存档：跑前备份、跑后还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-06_ui"
const SIZES := [Vector2i(480, 270), Vector2i(960, 540), Vector2i(1440, 810)]

var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# G0-02 多分辨率布局截图 %s" % Time.get_datetime_string_from_system())
	for sz in SIZES:
		await _capture_size(sz)
	var f := FileAccess.open("%s/capture_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	print("G0_UI|DONE shots=%d" % _lines.size())
	get_tree().quit(0)


func _capture_size(sz: Vector2i) -> void:
	get_window().size = sz
	await _wait_frames(6)
	await _wait(0.35)
	var tag := "%dx%d" % [sz.x, sz.y]
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = true
	add_child(duel)
	await _wait_frames(6)
	await _wait(0.35)

	await _shot(tag + "_01_loadout")

	duel._confirm_loadout()
	await _wait(0.8)
	# 长数值压力：换成长线，观察 HP / Lv 行是否溢出
	duel.player_hp_max = 999
	duel.player_hp = 999
	duel.growth.perk_ids.append("insight")
	duel.hud._refresh_meta()
	await _wait(0.3)
	await _shot(tag + "_02_battle_long")

	# 转轮中：P1 预览行（preview 预设）+ 洞察额外 +1 格
	duel.readability.apply_preset("preview")
	if not duel.reel_system.spinning:
		duel._on_spin_button_pressed()
	await _wait(0.45)
	await _shot(tag + "_03_spin_preview")

	# 战后三槽（卡片文案是否横向换行）
	duel.room_flow.begin_post_battle()
	await _wait(0.5)
	await _shot(tag + "_04_post_battle")

	# 替换弹层：用当前未装备的第一把武器
	var new_path := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			new_path = String(p)
			break
	if new_path != "":
		duel.hud.request_weapon_replace("替换武器", duel._weapon_info(new_path),
			func(_old: String) -> void: pass, new_path, func() -> void: pass)
		await _wait(0.5)
		await _shot(tag + "_05_replace_dialog")

	duel.queue_free()
	await _wait_frames(4)
	await _wait(0.3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_lines.append("%s  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
