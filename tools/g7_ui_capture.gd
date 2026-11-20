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
		duel._anvil_system.earn_directed_unlock("capture_test")
	await get_tree().process_frame
	var anvil = duel.hud.anvil_screen
	anvil.show_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	# 截图整屏（480x270 viewport 会被窗口放大，取实际视口）
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/anvil_directed.png"))
	print("G7 UI CAPTURED: ", OUT, "/anvil_directed.png")
	# 再截一张旧摇奖模式（验证互斥切换）
	if anvil.has_method("_on_mode_toggle"):
		anvil._on_mode_toggle()
		await get_tree().process_frame
		await get_tree().process_frame
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png(ProjectSettings.globalize_path(OUT + "/anvil_gacha.png"))
		print("G7 UI CAPTURED: ", OUT, "/anvil_gacha.png")
	get_tree().quit(0)
