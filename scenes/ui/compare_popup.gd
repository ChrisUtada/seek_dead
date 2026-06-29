class_name ComparePopup
extends Control

var _player_ref: Node2D
var _new_item: EquipmentBase
var _pending: bool = false


func init(player: Node2D, new_item: EquipmentBase):
	_player_ref = player
	_new_item = new_item
	_pending = true
	_build()


func _build():
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(640, 360)

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var panel = ColorRect.new()
	panel.position = Vector2(70, 80)
	panel.size = Vector2(500, 200)
	panel.color = Color(0.08, 0.08, 0.12, 0.95)
	add_child(panel)

	var title = Label.new()
	title.text = "装备对比"
	title.position = Vector2(200, 85)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 1, 0.6))
	add_child(title)

	_draw_item(Vector2(90, 115), _new_item, true)

	var mgr = _get_equip_manager()
	if mgr:
		var equipped = mgr.get_equipped(_new_item.slot) as EquipmentBase
		if equipped:
			_draw_item(Vector2(310, 115), equipped, false)

	var vs_label = Label.new()
	vs_label.text = "VS"
	vs_label.position = Vector2(240, 170)
	vs_label.add_theme_font_size_override("font_size", 18)
	vs_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	add_child(vs_label)

	_build_buttons()


func _draw_item(pos: Vector2, item: EquipmentBase, is_new: bool):
	var color = RarityTable.get_rarity_color(item.rarity)

	var border = ColorRect.new()
	border.position = pos
	border.size = Vector2(200, 150)
	border.color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.8)
	add_child(border)

	var title = Label.new()
	title.text = ("[新] " if is_new else "") + item.equipment_name
	title.position = pos + Vector2(4, 2)
	title.size = Vector2(192, 18)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", color)
	add_child(title)

	var y = 22
	var rarity_label = Label.new()
	rarity_label.text = RarityTable.get_rarity_name(item.rarity)
	rarity_label.position = pos + Vector2(4, y)
	rarity_label.add_theme_font_size_override("font_size", 10)
	rarity_label.add_theme_color_override("font_color", color)
	add_child(rarity_label)
	y += 16

	if item.set_id.length() > 0:
		var set_name = SetDatabase.get_set(item.set_id)
		if set_name:
			var set_label = Label.new()
			set_label.text = "套装: %s" % set_name.set_name
			set_label.position = pos + Vector2(4, y)
			set_label.add_theme_font_size_override("font_size", 10)
			set_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
			add_child(set_label)
			y += 16

	for affix in item.affixes:
		if y > 130:
			break
		var affix_label = Label.new()
		affix_label.text = "· " + affix.affix_name
		affix_label.position = pos + Vector2(4, y)
		affix_label.size = Vector2(192, 14)
		affix_label.add_theme_font_size_override("font_size", 9)
		affix_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		add_child(affix_label)
		y += 14


func _build_buttons():
	var btn_equip = _make_button(Vector2(90, 260), Vector2(120, 30), "替换装备", Color(0.2, 0.6, 0.3), _on_equip)
	var btn_keep = _make_button(Vector2(220, 260), Vector2(120, 30), "留在背包", Color(0.3, 0.3, 0.5), _on_keep)
	var btn_discard = _make_button(Vector2(350, 260), Vector2(120, 30), "丢弃", Color(0.6, 0.2, 0.2), _on_discard)


func _make_button(pos: Vector2, size: Vector2, text: String, color: Color, callback: Callable) -> Control:
	var container = Control.new()
	container.position = pos
	container.size = size
	add_child(container)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 11)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(label)

	container.gui_input.connect(_make_gui_handler(callback))

	return container


func _make_gui_handler(callback: Callable):
	return func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			callback.call()


func _on_equip():
	if not _pending or not _player_ref:
		return
	_pending = false
	var mgr = _get_equip_manager()
	if mgr:
		mgr.equip(_new_item)
	queue_free()


func _on_keep():
	if not _pending:
		return
	_pending = false
	queue_free()


func _on_discard():
	if not _pending or not _player_ref:
		return
	_pending = false
	var inv = _get_inventory()
	if inv:
		for i in range(inv.get_item_count()):
			if inv.get_item(i) == _new_item:
				inv.remove_item(i)
				break
	queue_free()


func _get_equip_manager() -> EquipmentManager:
	if not _player_ref:
		return null
	return _player_ref.get_node_or_null("EquipmentManager") as EquipmentManager


func _get_inventory() -> EquipmentInventory:
	if not _player_ref:
		return null
	return _player_ref.get_node_or_null("EquipmentInventory") as EquipmentInventory
