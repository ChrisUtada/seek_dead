extends Node

# ============================================================================
# 武器替换弹层实机探针（2026-11-08）
# 复现「棋盘武器替换窗口过大、底部按钮被裁掉」的问题，并量化：
#   HUD 尺寸 / 弹层面板矩形 / 每个子控件矩形 / 按钮是否落在屏幕内
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/replace_dialog_probe.tscn
# 产物：docs/baseline/2026-11-08_replace_dialog/{n}_{name}.png + probe_data.txt
# 会实例化 duel（可能写存档）：跑前把 APPDATA 指到临时目录。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_replace_dialog"

var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# 武器替换弹层探针 %s" % Time.get_datetime_string_from_system())
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

	var hud: BattleHud = duel.hud
	_note("HUD 尺寸", hud.size)
	_note("HUD 全局矩形", hud.get_global_rect())
	var slots: Array = duel.selected_loadout
	_note("当前武器槽", "%d 把" % slots.size())
	if slots.size() < 2:
		_note("中止", "武器槽不足 2 把，无法复现替换弹层")
		await _finish(duel)
		return
	var new_path := String(slots[0])
	var info: String = duel._weapon_info(new_path)
	_note("新武器信息行数", str(info.count("\n") + 1))

	# 与棋盘武器格/藏库/营地完全同一条调用路径
	hud.request_weapon_replace("武器藏库：替换武器", info,
		func(_old: String) -> void: pass, new_path,
		func() -> void: pass)
	await _wait_frames(4)
	await _wait(0.2)

	_dump_dialog(hud, "替换弹层")
	await _shot("01_replace_dialog")

	# 取消，回到战斗
	hud._on_replace_cancelled()
	await _wait_frames(2)

	# 最坏情况：新武器带锋铸/熟练/铭印/追赶多行，内容明显高于屏幕
	var long_info: String = info + "\n锋铸·锐：斩击 +2 格，代价 MISS 权重 +1" \
		+ "\n熟练 3/12（有效清房每房 +1）" + "\n铭印：连击起手 +1 回合" \
		+ "\n追赶：熟练 3 → 12（有效清房每房 +1）"
	hud.request_weapon_replace("武器藏库：替换武器", long_info,
		func(_old: String) -> void: pass, new_path,
		func() -> void: pass)
	await _wait_frames(4)
	await _wait(0.2)
	_dump_dialog(hud, "长内容弹层")
	var scroll: ScrollContainer = hud._replace_scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	_note("滚动条范围", "content=%.0f 可见=%.0f 可滚=%s" % [
		bar.max_value, scroll.size.y,
		"是" if bar.max_value > scroll.size.y + 0.5 else "否"])
	await _shot("02_long_dialog_top")
	# 滚到底：确认最后一行按钮能进入可视区
	scroll.scroll_vertical = 9999
	await _wait_frames(3)
	var cancel_btn: Button = hud._replace_vbox.get_child(hud._replace_vbox.get_child_count() - 1) as Button
	_note("滚到底后取消按钮", "rect=%s 全局可视=%s" % [
		str(cancel_btn.get_global_rect()),
		"是" if hud.get_global_rect().encloses(cancel_btn.get_global_rect()) else "否"])
	await _shot("03_long_dialog_bottom")
	hud._on_replace_cancelled()
	await _wait_frames(2)
	await _finish(duel)


func _dump_dialog(hud: BattleHud, tag: String) -> void:
	var dlg: PanelContainer = hud._replace_dialog
	var vbox: VBoxContainer = hud._replace_vbox
	if dlg == null or vbox == null:
		_note(tag, "弹层未构建")
		return
	_note(tag + " 可见", str(dlg.visible))
	_note(tag + " 内容最小尺寸", vbox.get_combined_minimum_size())
	_note(tag + " 内容实际尺寸", vbox.size)
	var center := dlg.get_child(0) as Control
	var panel := center.get_child(0) as Control
	_note(tag + " 面板矩形", panel.get_global_rect())
	var screen_h: float = hud.size.y
	_note(tag + " 屏幕高度", str(screen_h))
	var idx := 0
	for c in vbox.get_children():
		var ctrl := c as Control
		if ctrl == null:
			continue
		var r := ctrl.get_global_rect()
		var text := ""
		if ctrl is Label:
			text = String((ctrl as Label).text).replace("\n", "⏎").substr(0, 24)
		elif ctrl is Button:
			text = String((ctrl as Button).text)
		var inside: bool = r.position.y >= 0.0 and r.end.y <= screen_h + 0.5
		_note("%s 子%d %s" % [tag, idx, ctrl.get_class()],
			"rect=%s 屏内=%s %s" % [str(r), "是" if inside else "否", text])
		idx += 1


func _note(key: String, value) -> void:
	var line := "%s: %s" % [key, str(value)]
	_lines.append(line)
	print("PROBE|" + line)


func _finish(duel: Node) -> void:
	var f := FileAccess.open("%s/probe_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("PROBE|DONE")
	duel.queue_free()
	await _wait_frames(3)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT_DIR, name])
	_lines.append("%s  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
