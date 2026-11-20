extends Node

# 验证 2026-11-20 机制说明遮挡修复：直跳深渊监视者（长机制），截图
# 检查敌人面板机制 label 是否为短文本、TopBar 商店/下一房按钮是否可见。
# 运行（窗口模式）：Godot_v4.7-stable_win64.exe --path . res://tools/mechanic_fix_capture.tscn
const OUT := "res://docs/baseline/G7_2026-11-20_ui"
const BOSS := "res://resources/rooms/abyss_watcher.tres"

func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	# 直跳 BOSS
	var idx := -1
	for i in range(duel.ROOMS.size()):
		if String(duel.ROOMS[i].kind) == "boss":
			idx = i
			break
	if idx >= 0:
		duel.ROOMS[idx] = load(BOSS) as RoomData
		duel._start_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	# 显示 interroom 按钮（模拟战后态）
	duel.hud.set_interroom_enabled(true)
	await get_tree().process_frame
	# 代码级证据
	var lbl: Label = duel.hud.enemy_mechanic_label
	print("MECH_FIX|label_text_len=%d|text=%s" % [String(lbl.text).length(), lbl.text])
	print("MECH_FIX|label_visible=%s" % str(lbl.visible))
	print("MECH_FIX|tooltip_len=%d" % String(lbl.tooltip_text).length())
	print("MECH_FIX|shop_btn_visible=%s|next_btn_visible=%s" % [
		str(duel.hud.interroom_shop_btn.visible), str(duel.hud.interroom_next_btn.visible)])
	# 截图
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/mechanic_fix_boss.png"))
	print("MECH_FIX|CAPTURED")
	get_tree().quit(0)
