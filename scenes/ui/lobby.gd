extends CanvasLayer

var _container: Control
var _resource_labels: Dictionary = {}
var _forge_panel: Control = null
var _collection_panel: Control = null
var _panels_container: Control = null
var _all_buttons: Array[ColorRect] = []

const PANEL_NONE = -1
const PANEL_FORGE = 0
const PANEL_COLLECTION = 1
var _active_panel: int = PANEL_NONE


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_container = Control.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_build_ui()
	_container.modulate = Color(1, 1, 1, 0)
	var t = create_tween()
	t.tween_property(_container, "modulate", Color(1, 1, 1, 1), 0.3)


func _build_ui():
	var bg = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color(0.06, 0.06, 0.1, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bg)

	var title = Label.new()
	title.text = "补给站"
	title.position = Vector2(20, 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_font_size_override("font_size", 22)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Seek Dead — 局外基地"
	subtitle.position = Vector2(20, 48)
	subtitle.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(subtitle)

	_build_resources()
	_build_buttons()
	_build_panels()
	_panels_container.hide()


func _build_resources():
	var x = 320
	var y = 20
	var res_title = Label.new()
	res_title.text = "资源"
	res_title.position = Vector2(x, y)
	res_title.add_theme_font_size_override("font_size", 14)
	res_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	res_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(res_title)
	y += 22

	var resource_keys = [
		["gold", "金币", Color(1, 0.85, 0.3)],
		["iron", "铁碎片", Color(0.6, 0.6, 0.7)],
		["magic_essence", "魔法精华", Color(0.4, 0.5, 1)],
		["legendary_core", "传奇核心", Color(1, 0.4, 0.2)],
	]
	for pair in resource_keys:
		var key = pair[0] as String
		var label_text = pair[1] as String
		var color = pair[2] as Color
		var lbl = Label.new()
		lbl.name = "Res" + key
		lbl.position = Vector2(x, y)
		lbl.size = Vector2(200, 16)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(lbl)
		_resource_labels[key] = { "label": lbl, "name": label_text, "color": color }
		y += 18
	_refresh_resources()


func _refresh_resources():
	var data = SaveSystem.load_lobby_data()
	for key in _resource_labels:
		var entry = _resource_labels[key]
		var val = data.get(key, 0)
		entry.label.text = "%s: %s" % [entry.name, _fmt_num(val)]
		entry.label.add_theme_color_override("font_color", entry.color if val > 0 else Color(0.4, 0.4, 0.4))


func _fmt_num(v: int) -> String:
	if v >= 100000:
		return "%dk" % (v / 1000)
	return str(v)


func _build_buttons():
	var btn_data = [
		["开始旅程", Vector2(30, 90), Vector2(160, 24), Color(0.5, 0.1, 0.1),
		 func(): _on_start_run()],
		["锻造", Vector2(30, 126), Vector2(160, 24), Color(0.15, 0.35, 0.5),
		 func(): _on_open_forge()],
		["图鉴", Vector2(30, 162), Vector2(160, 24), Color(0.15, 0.4, 0.15),
		 func(): _on_open_collection()],
		["返回主菜单", Vector2(30, 300), Vector2(160, 24), Color(0.3, 0.3, 0.3),
		 func(): _on_back_to_menu()],
	]
	for d in btn_data:
		_make_button(d[0], d[1], d[2], d[3], d[4])


func _make_button(text: String, pos: Vector2, size: Vector2, color: Color, callback: Callable):
	var btn = ColorRect.new()
	btn.position = pos
	btn.size = size
	btn.color = color
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.add_child(btn)
	_all_buttons.append(btn)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(0, 0)
	label.size = size
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)

	btn.set_meta("callback", callback)


func _build_panels():
	_panels_container = Control.new()
	_panels_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.add_child(_panels_container)

	_forge_panel = _make_sub_panel(Vector2(200, 70), Vector2(420, 270),
		"锻造", Color(0.6, 0.8, 1), "装备升级/附魔/洗练/分解 — 敬请期待")
	_collection_panel = _make_sub_panel(Vector2(200, 70), Vector2(420, 270),
		"图鉴", Color(0.4, 1, 0.4), "装备收集进度 + 全局属性奖励 — 敬请期待")
	_forge_panel.hide()
	_collection_panel.hide()


func _make_sub_panel(pos: Vector2, size: Vector2, title_text: String,
		title_color: Color, hint_text: String) -> Control:
	var panel = Control.new()
	panel.position = pos
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panels_container.add_child(panel)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var title = Label.new()
	title.text = title_text
	title.position = Vector2(10, 10)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", title_color)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var hint = Label.new()
	hint.text = hint_text
	hint.position = Vector2(10, 50)
	hint.size = Vector2(400, 80)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hint)

	_make_panel_close_btn(panel, func(): _close_all_panels())
	return panel


func _make_panel_close_btn(parent: Control, callback: Callable):
	var btn = ColorRect.new()
	btn.position = Vector2(parent.size.x - 36, 6)
	btn.size = Vector2(30, 20)
	btn.color = Color(0.5, 0.15, 0.15)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(btn)
	_all_buttons.append(btn)
	btn.set_meta("callback", callback)

	var label = Label.new()
	label.text = "X"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mpos = event.position
		for btn in _all_buttons:
			if not is_instance_valid(btn):
				continue
			if _rect_contains(btn, mpos):
				var cb = btn.get_meta("callback") as Callable
				if cb:
					cb.call()
				return

		if _active_panel != PANEL_NONE and _panels_container:
			var p = _forge_panel if _active_panel == PANEL_FORGE else _collection_panel
			if not _rect_contains(p, mpos):
				_close_all_panels()


func _rect_contains(node: Node, point: Vector2) -> bool:
	if not node is Control:
		return false
	var c = node as Control
	return point.x >= c.position.x and point.x <= c.position.x + c.size.x \
		and point.y >= c.position.y and point.y <= c.position.y + c.size.y


func _on_start_run():
	SaveSystem.delete_save()
	SceneManager.fade_to_scene("res://scenes/game/game.tscn")


func _on_open_forge():
	_close_all_panels()
	_active_panel = PANEL_FORGE
	_panels_container.show()
	_forge_panel.show()


func _on_open_collection():
	_close_all_panels()
	_active_panel = PANEL_COLLECTION
	_panels_container.show()
	_collection_panel.show()


func _close_all_panels():
	_active_panel = PANEL_NONE
	if _panels_container:
		_panels_container.hide()


func _on_back_to_menu():
	SceneManager.fade_to_scene("res://scenes/ui/main_menu.tscn")
