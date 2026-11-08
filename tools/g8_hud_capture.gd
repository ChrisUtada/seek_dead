extends Node

# ============================================================================
# G8-01 HUD 拆分实机采集（2026-11-08）
# 验证 popup_pool / symbol_tooltip / screen.gd 退役后布局未变：
#   战斗 HUD / 符号 tooltip / 飘字 / 失败覆盖层
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/g8_hud_capture.tscn
# 产物：docs/baseline/2026-11-08_g8_hud/{n}_{name}.png + capture_data.txt
# 会写存档：跑前备份、跑后还原。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_g8_hud"

var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# G8-01 HUD 拆分实机截图 %s" % Time.get_datetime_string_from_system())
	get_window().size = Vector2i(960, 540)
	await _wait_frames(6)
	await _wait(0.35)

	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = true
	add_child(duel)
	await _wait_frames(6)
	await _wait(0.35)
	duel._confirm_loadout()
	await _wait(0.9)
	await _shot("01_battle")

	# 符号 tooltip：悬停首列首行（元素/克制文案与定位）
	duel.hud._on_cell_hover(0, 0)
	await _wait(0.2)
	await _shot("02_symbol_tooltip")
	duel.hud._on_cell_unhover()

	# 飘字：真实借出池 Label，取玩家锚点
	duel.hud._popup("❤+3", Palette.POP_HEAL, duel.hud._player_sprite_anchor())
	await _wait(0.12)
	await _shot("03_popup")

	# 失败覆盖层（screen.gd 退役后：背景 + 居中 VBox）
	duel.hud._show_overlay("战斗失败", "回整备")
	await _wait(0.25)
	await _shot("04_overlay")
	duel.hud._hide_overlay()

	var f := FileAccess.open("%s/capture_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	print("G8_HUD|DONE shots=%d" % _lines.size())
	duel.queue_free()
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
