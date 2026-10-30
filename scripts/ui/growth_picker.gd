extends Control

# 成长结算覆盖层（M2-03）：房间胜利后于间歇前弹出一次，合并技艺三选一与武器铭印。
# 每个 section 为一组单选（key 区分：技艺 "perk" / 武器路径），全部选定后方可确认；确认一次性回调 {key: id}。
# 候选在展示时已定完整效果（含真实格数与共鸣变化的预览文案）。
# 由 BattleHud.show_growth_settlement 懒构建（不注册全局 class_name，同 meta_screen 之外的 UI 覆盖层约定）。

const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

var _vbox: VBoxContainer
var _confirm_btn: Button = null
var _picked: Dictionary = {}          # key -> 已选 id
var _section_keys: Array = []         # 需要选择的 key（顺序同展示）
var _on_confirm: Callable = Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 95   # 高于覆盖层（90），低于掌机外壳（100）
	var shade := ColorRect.new()
	shade.color = Palette.BG_OVERLAY
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var dlg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACCENT_GOLD
	sb.set_border_width_all(2)
	dlg.add_theme_stylebox_override("panel", sb)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	dlg.add_child(_vbox)
	center.add_child(dlg)
	visible = false


# sections: [{"key": String, "title": String, "sub": String, "choices": [{id, family, name, desc}]}]
# on_confirm: Callable(picked: Dictionary)  —— 每个 key 都选定后才可确认。
func show_sections(title: String, sections: Array, on_confirm: Callable) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	_picked = {}
	_section_keys = []
	_on_confirm = on_confirm
	_vbox.add_child(_text_label(title, TypeScale.OVERLAY, Palette.ACCENT_GOLD))
	for sec in sections:
		var key: String = sec["key"]
		_section_keys.append(key)
		_vbox.add_child(_text_label(sec["title"], TypeScale.MEDIUM, Palette.ACCENT_GOLD))
		_vbox.add_child(_text_label(sec["sub"], TypeScale.TINY, Palette.MUTED))
		var group := ButtonGroup.new()
		for opt in sec["choices"]:
			var btn = UI_BUTTON.instantiate()
			btn.text = "[%s] %s\n%s" % [opt["family"], opt["name"], opt["desc"]]
			btn.toggle_mode = true
			btn.button_group = group
			btn.toggled.connect(_on_toggled.bind(key, opt["id"]))
			_vbox.add_child(btn)
	_confirm_btn = UI_BUTTON.instantiate()
	_confirm_btn.text = "确认成长"
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_vbox.add_child(_confirm_btn)
	visible = true


func hide_picker() -> void:
	visible = false


func _on_toggled(on: bool, key: String, id: String) -> void:
	if not on:
		return
	_picked[key] = id
	_confirm_btn.disabled = _picked.size() < _section_keys.size()


func _on_confirm_pressed() -> void:
	if _picked.size() < _section_keys.size():
		return
	visible = false
	_on_confirm.call(_picked.duplicate())


func _text_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
