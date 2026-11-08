extends Node

# ============================================================================
# 整备屏排版验收取证（G8 第三切片，2026-11-08）
# 目的：用真实节点尺寸定位「物品卡文字被裁切」「卡片/滚动条/底部栏重叠」等问题，
#       并在 480x270 / 960x540 / 1440x810 三档窗口下各取一张。
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/loadout_layout_probe.tscn
# 产物：docs/baseline/2026-11-08_loadout/{name}.png + probe_data.txt
# 会实例化 duel（可能写存档）：跑前把 APPDATA 指到临时目录。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_loadout"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const CATS := ["weapon", "skill", "active", "passive"]

var _duel: DuelController
var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# 整备屏排版取证 %s" % Time.get_datetime_string_from_system())

	_duel = load(DUEL_SCENE).instantiate() as DuelController
	_duel.demo_config.enabled = true
	add_child(_duel)
	await _wait(0.6)

	var sizes: Array[Vector2i] = [Vector2i(480, 270), Vector2i(960, 540), Vector2i(1440, 810)]
	for res in sizes:
		get_window().size = res
		await _wait(0.5)
		var tag: String = "%dx%d" % [res.x, res.y]
		var lo: LoadoutScene = _duel.hud.loadout_screen

		lo._set_sub_open(false, true)
		await _wait(0.25)
		await _shot("main_%s" % tag)
		_dump("main_%s" % tag, lo)

		for cat in CATS:
			lo._open_sub(cat)
			await _wait(0.35)
			await _shot("%s_%s" % [cat, tag])
			_dump("%s_%s" % [cat, tag], lo)
			lo._set_sub_open(false, true)
			await _wait(0.2)

		# 叠层：转轮带预览 / 生涯成就 / 铸式（是否超出 480x270、内容是否需要滚动）
		lo._preview_panel.visible = true
		lo._refresh_preview()
		await _wait(0.35)
		await _shot("preview_%s" % tag)
		_dump_overlay("preview_%s" % tag, lo._preview_panel)
		lo._preview_panel.visible = false

		lo._toggle_career()
		await _wait(0.35)
		await _shot("career_%s" % tag)
		_dump_overlay("career_%s" % tag, lo._career_panel)
		lo._toggle_career()

		lo._toggle_forge()
		await _wait(0.35)
		await _shot("forge_%s" % tag)
		_dump_overlay("forge_%s" % tag, lo._forge_panel)
		lo._toggle_forge()
		await _wait(0.2)

		# 换类目后列表是否回顶（技能滚到底 → 切武器）
		lo._open_sub("skill")
		await _wait(0.3)
		var sc: ScrollContainer = lo.sub_scroll
		sc.scroll_vertical = 10000
		await _wait(0.2)
		var before: int = sc.scroll_vertical
		lo._open_sub("weapon")
		await _wait(0.3)
		_lines.append("\n## scroll_reset_%s before=%d after=%d %s" % [
			tag, before, sc.scroll_vertical,
			"OK" if sc.scroll_vertical == 0 else "STALE"])
		lo._set_sub_open(false, true)
		await _wait(0.2)

	# ui_button 主题字号修正的影响面：奖励屏「跳过」按钮（不依赖局内状态，直接量字号）
	var skip: Button = _duel.hud.reward_screen._skip_btn
	_lines.append("\n## ui_button_font skip_btn font=%d min=%s" % [
		skip.get_theme_font_size("font_size"), skip.custom_minimum_size])

	get_window().size = Vector2i(960, 540)
	await _wait(0.4)
	_duel.board_config.enabled = true
	_duel._confirm_loadout()
	await _wait(1.2)
	await _shot("board_960x540")
	var f := FileAccess.open("%s/probe_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("LOADOUT_PROBE|DONE lines=%d" % _lines.size())
	_duel.queue_free()
	await _wait_frames(4)
	get_tree().quit(0)


func _dump(name: String, lo: LoadoutScene) -> void:
	_lines.append("\n## %s" % name)
	var win := get_window().size
	var ui: Control = lo.ui_root
	_lines.append("window=%s ui_root=%s" % [win, ui.size])
	_lines.append("sub_panel rect=%s" % [Rect2(lo.sub_panel.position, lo.sub_panel.size)])
	_lines.append("sub_list size=%s  scroll=%s" % [
		lo.sub_list.size, lo.sub_list.get_parent().size])
	var cards: Array = lo.loadout_cards
	_lines.append("cards=%d sub_list_children=%d" % [cards.size(), lo.sub_list.get_child_count()])
	for i in range(cards.size()):
		var btn: Button = cards[i]["btn"]
		if not is_instance_valid(btn):
			continue
		var font_size: int = btn.get_theme_font_size("font_size")
		var font: Font = btn.get_theme_font("font")
		var sb: StyleBox = btn.get_theme_stylebox("normal")
		var icon_w: float = btn.icon.get_width() + btn.get_theme_constant("h_separation") if btn.icon != null else 0.0
		var avail: float = btn.size.x - sb.content_margin_left - sb.content_margin_right - icon_w
		_lines.append("  card%d size=%s min=%s font=%d lines=%d avail=%.1f icon=%.1f" % [
			i, btn.size, btn.get_combined_minimum_size(), font_size,
			btn.text.count("\n") + 1, avail, icon_w])
		_lines.append("    autowrap=%d clip=%s" % [btn.autowrap_mode, btn.clip_text])
		var idx := 0
		for line in btn.text.split("\n"):
			var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_lines.append("    L%d w=%.1f %s | %s" % [
				idx, w, "OVERFLOW" if w > avail else "ok", line])
			idx += 1
		# 自动换行后的真实占用（Button 无逐行接口，用 get_multiline_string_size 估算）
		var wrapped: Vector2 = font.get_multiline_string_size(
			btn.text, HORIZONTAL_ALIGNMENT_CENTER, avail, font_size)
		var need_h: float = wrapped.y + sb.content_margin_top + sb.content_margin_bottom
		_lines.append("    wrapped=%.1fx%.1f need_h=%.1f card_h=%.1f %s" % [
			wrapped.x, wrapped.y, need_h, btn.size.y,
			"CLIPPED" if need_h > btn.size.y + 0.5 else "fits"])
		if i == 0:
			var tip: Control = btn._make_custom_tooltip(btn.tooltip_text)
			_lines.append("    tooltip_ok=%s len=%d" % [
				tip != null and tip is RichTextLabel, btn.tooltip_text.length()])
			if tip != null:
				tip.free()
	# 底部栏
	var bar: HBoxContainer = lo.count_label.get_parent()
	_lines.append("bottom_bar rect=%s" % [Rect2(bar.position, bar.size)])
	for c in bar.get_children():
		var ctl := c as Control
		if ctl == null:
			continue
		var txt: String = ""
		if ctl is Label:
			txt = (ctl as Label).text
		elif ctl is Button:
			txt = (ctl as Button).text
		_lines.append("  bar_child %s rect=%s text=%s" % [
			ctl.name, Rect2(ctl.position, ctl.size), txt])


func _dump_overlay(name: String, panel: Control) -> void:
	_lines.append("\n## %s" % name)
	if panel == null:
		_lines.append("panel=null")
		return
	var ui: Control = _duel.hud.loadout_screen.ui_root
	_lines.append("screen=%s panel=%s visible=%s" % [
		ui.size, Rect2(panel.position, panel.size), panel.visible])
	var scroll: ScrollContainer = _find_scroll(panel)
	if scroll == null:
		_lines.append("scroll=(none)")
		return
	var box: Control = null
	for c in scroll.get_children():
		box = c as Control
		break
	var box_min: Vector2 = box.get_combined_minimum_size() if box != null else Vector2.ZERO
	_lines.append("scroll rect=%s  content_min=%s  %s" % [
		Rect2(scroll.global_position - panel.global_position, scroll.size), box_min,
		"NEEDS_SCROLL" if box_min.y > scroll.size.y + 0.5 else "fits"])


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


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
