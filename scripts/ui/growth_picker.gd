extends Control

# 技艺三选一覆盖层（M2-01）：历练升级时在房间间歇前弹出；候选在展示时已定完整效果，点选后回调。
# 由 BattleHud.show_growth_picker 懒构建（不注册全局 class_name，同 meta_screen 之外的 UI 覆盖层约定）。

signal perk_chosen(id: String)

const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

var _vbox: VBoxContainer


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


# 通用三选一（技艺 / 铭印共用）：title 与 sub 由调用方给出；候选字段 id / family / name / desc。
func show_choices(title: String, sub: String, choices: Array, on_chosen: Callable) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	_vbox.add_child(_text_label(title, TypeScale.OVERLAY, Palette.ACCENT_GOLD))
	_vbox.add_child(_text_label(sub, TypeScale.TINY, Palette.MUTED))
	for opt in choices:
		var btn = UI_BUTTON.instantiate()
		btn.text = "[%s] %s\n%s" % [opt["family"], opt["name"], opt["desc"]]
		btn.pressed.connect(_on_pressed.bind(opt["id"], on_chosen))
		_vbox.add_child(btn)
	visible = true


func hide_picker() -> void:
	visible = false


func _on_pressed(id: String, on_chosen: Callable) -> void:
	visible = false
	on_chosen.call(id)


func _text_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
