class_name EquipmentPanel
extends Control

var _player_ref: Node2D
var _slot_widgets: Dictionary = {}
var _bag_grid: Control
var _stat_labels: Dictionary = {}
var _bag_slot_controls: Array = []
var _bag_items: Array = []
enum DragSource { NONE, BAG, EQUIP }
var _drag_source = DragSource.NONE
var _drag_index: int = -1
var _drag_slot: int = -1
var _drag_start_pos: Vector2

const SLOT_POS: Dictionary = {
	EquipmentEnums.EquipmentSlot.HELMET: Vector2(40, 40),
	EquipmentEnums.EquipmentSlot.ACCESSORY_1: Vector2(40, 100),
	EquipmentEnums.EquipmentSlot.BODY: Vector2(40, 160),
	EquipmentEnums.EquipmentSlot.WEAPON_MAIN: Vector2(40, 220),
	EquipmentEnums.EquipmentSlot.WEAPON_OFFHAND: Vector2(40, 280),
	EquipmentEnums.EquipmentSlot.HAND: Vector2(220, 40),
	EquipmentEnums.EquipmentSlot.LEG: Vector2(220, 100),
	EquipmentEnums.EquipmentSlot.ACCESSORY_2: Vector2(220, 160),
}


func init(player: Node2D):
	_player_ref = player
	_build()


func _build():
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(640, 360)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_slots()
	_build_stats()
	_build_backpack()


func _build_slots():
	for slot in SLOT_POS.keys():
		var pos = SLOT_POS[slot]
		var container = Control.new()
		container.position = pos
		container.size = Vector2(150, 50)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)

		var label = Label.new()
		label.text = EquipmentEnums.SLOT_NAMES.get(slot, "?")
		label.position = Vector2(0, -14)
		label.add_theme_font_size_override("font_size", 10)
		label.modulate = Color(0.6, 0.6, 0.6)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)

		var slot_bg = ColorRect.new()
		slot_bg.position = Vector2(0, 0)
		slot_bg.size = Vector2(148, 46)
		slot_bg.color = Color(0.15, 0.15, 0.2, 0.8)
		slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(slot_bg)

		var name_label = Label.new()
		name_label.position = Vector2(4, 2)
		name_label.size = Vector2(140, 20)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(name_label)

		var affix_label = Label.new()
		affix_label.position = Vector2(4, 22)
		affix_label.size = Vector2(140, 20)
		affix_label.add_theme_font_size_override("font_size", 9)
		affix_label.modulate = Color(0.8, 0.8, 0.8)
		affix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(affix_label)

		_slot_widgets[slot] = { "name": name_label, "affix": affix_label, "bg": slot_bg }

	_refresh_slots()


func _refresh_slots():
	var mgr = _get_equip_manager()
	if not mgr:
		return
	for slot in SLOT_POS.keys():
		var w = _slot_widgets.get(slot)
		if not w:
			continue
		var item = mgr.get_equipped(slot) as EquipmentBase
		if item:
			var color = RarityTable.get_rarity_color(item.rarity)
			w.name.text = item.equipment_name
			w.name.modulate = color
			w.bg.color = Color(color.r * 0.2, color.g * 0.2, color.b * 0.2, 0.8)
			var parts: Array[String] = []
			for aff in item.affixes:
				parts.append(aff.affix_name)
			w.affix.text = ", ".join(parts)
		else:
			w.name.text = "空"
			w.name.modulate = Color(0.4, 0.4, 0.4)
			w.bg.color = Color(0.15, 0.15, 0.2, 0.8)
			w.affix.text = ""


func _build_stats():
	var x = 420
	var y = 30
	var title = Label.new()
	title.text = "属性"
	title.position = Vector2(x, y)
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	y += 25

	var stat_keys = [
		"max_hp", "hp_regen", "max_energy", "energy_regen",
		"max_stamina", "stamina_regen", "heat_cooling",
	]
	for key in stat_keys:
		var lbl = Label.new()
		lbl.position = Vector2(x, y)
		lbl.size = Vector2(180, 18)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		_stat_labels[key] = lbl
		y += 17


func _build_backpack():
	var y = 280
	var title = Label.new()
	title.text = "背包"
	title.position = Vector2(20, y)
	title.add_theme_font_size_override("font_size", 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	y += 22

	_bag_grid = Control.new()
	_bag_grid.position = Vector2(20, y)
	_bag_grid.size = Vector2(600, 60)
	_bag_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bag_grid)
	_refresh_backpack()


func _refresh_backpack():
	for c in _bag_slot_controls:
		if is_instance_valid(c):
			c.queue_free()
	_bag_slot_controls.clear()
	_bag_items.clear()

	var inv = _get_inventory()
	if not inv:
		return
	var slot_size = Vector2(46, 46)
	var gap = 4
	var cols = 6
	var row = 0
	for i in range(inv.get_item_count()):
		var col = i % cols
		if col == 0 and i > 0:
			row += 1
		var item = inv.get_item(i)
		if not item:
			continue
		var slot = Control.new()
		slot.position = Vector2(col * (slot_size.x + gap), row * (slot_size.y + gap))
		slot.size = slot_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg = ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color = RarityTable.get_rarity_color(item.rarity)
		bg.color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9)
		slot.add_child(bg)
		var name_lbl = Label.new()
		name_lbl.position = Vector2(2, 2)
		name_lbl.size = slot_size - Vector2(4, 4)
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.text = item.equipment_name.substr(0, 6)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(name_lbl)
		_bag_slot_controls.append(slot)
		_bag_items.append({ "index": i, "item": item, "rect": Rect2(slot.position, slot.size) })
		_bag_grid.add_child(slot)


func refresh():
	_refresh_slots()
	_refresh_backpack()
	var state = _get_state()
	if not state:
		return
	var val_map = {
		"max_hp": "%.0f" % state.max_hp,
		"hp_regen": "%.1f" % state.hp_regen,
		"max_energy": "%.0f" % state.max_energy,
		"energy_regen": "%.1f" % state.energy_regen,
		"max_stamina": "%.0f" % state.max_stamina,
		"stamina_regen": "%.1f" % state.stamina_regen,
		"heat_cooling": "%.1f" % state.heat_cooling,
	}
	var label_map = {
		"max_hp": "HP上限", "hp_regen": "HP回复/秒", "max_energy": "能量上限",
		"energy_regen": "能量回复/秒", "max_stamina": "体力上限",
		"stamina_regen": "体力回复/秒", "heat_cooling": "热量冷却",
	}
	for key in val_map:
		var lbl = _stat_labels.get(key)
		if not lbl:
			continue
		lbl.text = "%s: %s" % [label_map.get(key, key), val_map[key]]


func _get_equip_manager() -> EquipmentManager:
	if not _player_ref:
		return null
	return _player_ref.get_node_or_null("EquipmentManager") as EquipmentManager


func _get_state() -> StateComponent:
	if not _player_ref:
		return null
	return _player_ref.get_node_or_null("StateComponent") as StateComponent


func _get_inventory() -> EquipmentInventory:
	if not _player_ref:
		return null
	return _player_ref.get_node_or_null("EquipmentInventory") as EquipmentInventory


func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_source = DragSource.NONE
			_drag_index = _bag_slot_at_position(event.position)
			if _drag_index >= 0:
				_drag_source = DragSource.BAG
				_drag_start_pos = event.position
			else:
				var es = _equip_slot_at_position(event.position)
				if es >= 0 and _get_equip_manager():
					if _get_equip_manager().get_equipped(es) != null:
						_drag_source = DragSource.EQUIP
						_drag_slot = es
						_drag_start_pos = event.position
		elif _drag_source != DragSource.NONE:
			_end_drag(event.position)

	if event is InputEventMouseMotion and _drag_source != DragSource.NONE:
		if event.position.distance_to(_drag_start_pos) > 8:
			mouse_default_cursor_shape = CURSOR_DRAG


func _bag_slot_at_position(pos: Vector2) -> int:
	for i in range(_bag_items.size()):
		var entry = _bag_items[i]
		var global_rect = Rect2(_bag_grid.position + entry.rect.position, entry.rect.size)
		if global_rect.has_point(pos):
			return i
	return -1


func _equip_slot_at_position(pos: Vector2) -> int:
	for slot in SLOT_POS.keys():
		var slot_rect = Rect2(SLOT_POS[slot], Vector2(150, 50))
		if slot_rect.has_point(pos):
			return slot
	return -1


func _end_drag(mouse_pos: Vector2):
	mouse_default_cursor_shape = CURSOR_ARROW
	match _drag_source:
		DragSource.BAG:
			_drop_bag_to_slot(mouse_pos)
		DragSource.EQUIP:
			_drop_equip_to_bag()
	_drag_source = DragSource.NONE
	_drag_index = -1
	_drag_slot = -1


func _drop_bag_to_slot(mouse_pos: Vector2):
	if _drag_index < 0 or _drag_index >= _bag_items.size():
		return
	var entry = _bag_items[_drag_index]
	var item = entry.item as EquipmentBase
	if not item:
		return
	var target_slot = _equip_slot_at_position(mouse_pos)
	if target_slot < 0 or target_slot != item.slot:
		return

	var mgr = _get_equip_manager()
	var inv = _get_inventory()
	if not mgr or not inv:
		return

	var old_item = mgr.get_equipped(target_slot) as EquipmentBase
	inv.remove_item(entry.index)
	mgr.equip(item)
	if old_item:
		inv.add_item(old_item)
	refresh()


func _drop_equip_to_bag():
	var mgr = _get_equip_manager()
	var inv = _get_inventory()
	if not mgr or not inv:
		return
	var item = mgr.get_equipped(_drag_slot) as EquipmentBase
	if not item:
		return
	mgr.unequip(_drag_slot)
	if inv.has_space():
		inv.add_item(item)
	refresh()
