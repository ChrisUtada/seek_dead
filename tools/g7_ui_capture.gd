extends Node

# G7-3/4 UI 目视取证：窗口模式截图定向解锁面板 + 整备 tooltip。
# 运行：Godot_v4.7-stable_win64.exe --path . res://tools/g7_ui_capture.tscn
# （必须窗口模式，headless 无帧缓冲截图为空）

const OUT := "res://docs/baseline/G7_2026-11-20_ui"

func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	# 给 3 次定向额度，让候选按钮可见
	for i in range(3):
		duel._career.earn_directed("capture_test")
	await get_tree().process_frame
	duel.hud._show_career_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/career_directed.png"))
	print("G7 UI CAPTURED: ", OUT, "/career_directed.png")
	get_tree().quit(0)
