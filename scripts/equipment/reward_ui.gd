class_name RewardUI
extends CanvasLayer

var _items: Array[EquipmentBase] = []
var _panel: Control
var _buttons: Array[Button] = []
var _callback: Callable
var _ready_to_choose: bool = false
var _hint: Label


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50


func show_reward(items: Array[EquipmentBase], on_chosen: Callable):
	_items = items
	_callback = on_chosen
	_build_ui()
	_play_entrance()


func _play_entrance():
	var bg = _panel.get_child(0) as ColorRect
	if bg:
		bg.modulate = Color(0, 0, 0, 0)
		var tween = create_tween()
		tween.tween_property(bg, "modulate", Color(0, 0, 0, 0.7), 0.3)
		tween.tween_interval(0.4)
		tween.tween_callback(func():
			_ready_to_choose = true
			if _hint:
				_hint.text = "选择奖励"
		)


func _build_ui():
	var viewport = get_viewport()
	if not viewport:
		return
	var v_size = viewport.get_visible_rect().size

	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)

	_hint = Label.new()
	_hint.text = "稍等..."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.position = Vector2(0, v_size.y * 0.25)
	_hint.size = Vector2(v_size.x, 40)
	_panel.add_child(_hint)

	var card_w = 180
	var card_h = 220
	var total_w = _items.size() * card_w + (_items.size() - 1) * 16
	var start_x = (v_size.x - total_w) / 2

	for i in range(_items.size()):
		var item = _items[i]
		var btn = Button.new()
		btn.position = Vector2(start_x + i * (card_w + 16), v_size.y * 0.35)
		btn.size = Vector2(card_w, card_h)
		btn.theme_type_variation = &""
		var color = RarityTable.get_rarity_color(item.rarity)
		btn.modulate = Color(1, 1, 1, 0)
		set_button_style(btn, color)
		btn.text = _format_card(item)
		btn.disabled = true
		btn.pressed.connect(_on_choice.bind(i))
		_panel.add_child(btn)
		_buttons.append(btn)
		var target_y = btn.position.y
		btn.position.y = v_size.y
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "position:y", target_y, 0.25).set_delay(0.1 + i * 0.08).set_trans(Tween.TRANS_BACK)
		tween.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.2).set_delay(0.1 + i * 0.08)


func set_button_style(btn: Button, border_color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.25, 0.25, 0.3, 0.95)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_font_size_override("font_size", 14)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _format_card(item: EquipmentBase) -> String:
	var slot_name = EquipmentEnums.SLOT_NAMES.get(item.slot, "?")
	var rarity_name = RarityTable.get_rarity_name(item.rarity)
	var text = "%s\n" % item.equipment_name
	text += "%s %s\n" % [rarity_name, slot_name]
	text += "----------------\n"
	for affix in item.affixes:
		text += "%s\n" % affix.affix_name if affix.affix_name else ""
		if affix.affix_description:
			text += "  " + affix.affix_description + "\n"
	if item.affixes.is_empty():
		text += "无词缀\n"
	return text


func _on_choice(index: int):
	if not _ready_to_choose:
		return
	if index < 0 or index >= _items.size():
		return
	if _callback.is_null():
		return
	_ready_to_choose = false
	for btn in _buttons:
		btn.disabled = true
	_callback.call(_items[index])
	_close()


func _close():
	for btn in _buttons:
		btn.queue_free()
	_buttons.clear()
	if _panel:
		_panel.queue_free()
		_panel = null
	queue_free()
