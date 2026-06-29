class_name RewardUI
extends CanvasLayer

var _items: Array[EquipmentBase] = []
var _panel: Control
var _buttons: Array[Button] = []
var _callback: Callable


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50


func show_reward(items: Array[EquipmentBase], on_chosen: Callable):
	_items = items
	_callback = on_chosen
	_build_ui()


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

	var title = Label.new()
	title.text = "选择奖励"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.position = Vector2(0, v_size.y * 0.25)
	title.size = Vector2(v_size.x, 40)
	_panel.add_child(title)

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
		btn.modulate = Color(1, 1, 1, 1)
		set_button_style(btn, color)
		btn.text = _format_card(item)
		btn.pressed.connect(_on_choice.bind(i))
		_panel.add_child(btn)
		_buttons.append(btn)


func set_button_style(btn: Button, border_color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_font_size_override("font_size", 14)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _format_card(item: EquipmentBase) -> String:
	var slot_name = EquipmentEnums.SLOT_NAMES.get(item.slot, "?")
	var rarity_name = RarityTable.get_rarity_name(item.rarity)
	var text = "[%s]\n" % item.equipment_name
	text += "%s %s\n" % [rarity_name, slot_name]
	text += "─" * 16 + "\n"
	for affix in item.affixes:
		text += affix.affix_name + ": " + affix.affix_description + "\n"
	if item.affixes.is_empty():
		text += "无词缀\n"
	return text


func _on_choice(index: int):
	if index < 0 or index >= _items.size():
		return
	if _callback.is_null():
		return
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
