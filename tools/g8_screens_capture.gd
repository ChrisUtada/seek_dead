extends Node

# ============================================================================
# G8-05 商店 / 奖励 / 铁砧+图鉴 / 局末 实机采集（2026-11-09）
# 与 tests/g8_screens_layout_test.gd 配套：测试锁几何条件，本工具出图供肉眼验收。
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/g8_screens_capture.tscn
# 产物：docs/baseline/2026-11-09_g8_screens/{name}.png + capture_data.txt
# 会实例化 duel（可能写存档）：跑前把 APPDATA 指到临时目录。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-09_g8_screens"

var _lines: Array[String] = []
var _duel: DuelController


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# G8-05 四屏实机截图 %s" % Time.get_datetime_string_from_system())
	get_window().size = Vector2i(960, 540)
	await _wait_frames(6)
	await _wait(0.3)

	_duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	_duel.demo_config.enabled = true
	add_child(_duel)
	await _wait_frames(6)
	await _wait(0.3)
	_duel._confirm_loadout()
	await _wait(0.9)

	# ---- 商店 ----
	_duel._shop_system.roll_shop()
	_duel.hud._show_shop_screen()
	await _wait(0.45)
	await _shot("01_shop_buy")
	_duel.hud.shop_screen.show_tab("sell")
	await _wait(0.2)
	await _shot("02_shop_sell")
	_duel.hud.shop_screen.show_tab("buy")
	_duel.hud.hide_shop_screen()
	await _wait(0.35)

	# ---- 战后成长三槽 ----
	_duel.growth.xp = 2
	_duel.room_flow.begin_post_battle()
	await _wait(0.45)
	await _shot("03_reward_post_battle")
	if _duel.room_flow.post_battle_active:
		_duel._on_reward_skip_pressed()
	await _wait(0.35)
	_duel.hud.hide_reward_screen()

	# ---- BOSS 战利品 ----
	var boss_idx := -1
	for i in range(_duel.ROOMS.size()):
		if _duel.ROOMS[i].kind == "boss":
			boss_idx = i
			break
	if boss_idx >= 0:
		_duel.room_index = boss_idx
		_duel.hud._show_reward_screen(true)
		await _wait(0.45)
		await _shot("04_reward_boss")
		_duel.hud.hide_reward_screen()

	# ---- 铁砧 + 图鉴 ----
	_duel.hud._show_anvil_screen()
	await _wait(0.4)
	await _shot("05_anvil")
	var a: AnvilScreen = _duel.hud.anvil_screen
	a._toggle_codex()
	await _wait(0.35)
	await _shot("06_anvil_codex_weapon")
	a._set_codex_kind("passive")
	await _wait(0.25)
	await _shot("07_anvil_codex_passive")
	a._toggle_codex()
	_duel.hud.hide_anvil_screen()

	# ---- 局末 ----
	if _duel._career != null:
		_duel._career._unlock_charges = 0
	_duel.hud._show_meta_choice()
	await _wait(0.45)
	await _shot("08_meta")
	_duel.hud.hide_meta_screen()

	var f := FileAccess.open("%s/capture_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("G8_SCREENS_CAPTURE|DONE shots=%d" % _lines.size())
	_duel.queue_free()
	await _wait_frames(4)
	get_tree().quit(0)


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
