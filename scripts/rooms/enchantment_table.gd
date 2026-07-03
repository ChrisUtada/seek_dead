class_name EnchantmentTable
extends Area2D

const REROLL_COST: int = 300

var _player_near: bool = false
var _panel: Control = null


func _ready():
	collision_layer = 0
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	tree_exiting.connect(_close_panel)
	call_deferred("_build_visual")


func _build_visual():
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	shape.shape = rect
	add_child(shape)

	var bg = ColorRect.new()
	bg.size = Vector2(28, 28)
	bg.color = Color(0.6, 0.4, 0.2, 0.8)
	bg.position = Vector2(-14, -14)
	add_child(bg)

	var label = Label.new()
	label.text = "⚒"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-14, -16)
	label.size = Vector2(28, 28)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	add_child(label)


func _on_body_entered(body: Node2D):
	if not body.is_in_group("player"):
		return
	_player_near = true
	_open_panel()


func _on_body_exited(body: Node2D):
	if not body.is_in_group("player"):
		return
	_player_near = false
	_close_panel()


func _open_panel():
	if _panel:
		return
	var lobby_data = SaveSystem.load_lobby_data()
	var gold = lobby_data.get("gold", 0)

	var root = get_tree().current_scene

	_panel = Control.new()
	_panel.name = "EnchantPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)

	var frame = ColorRect.new()
	frame.size = Vector2(300, 200)
	frame.position = Vector2(170, 80)
	frame.color = Color(0.1, 0.1, 0.15, 0.95)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(frame)

	var title = Label.new()
	title.name = "Title"
	title.text = "附魔台  (金币: %d)" % gold
	title.position = Vector2(180, 90)
	title.size = Vector2(280, 20)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_panel.add_child(title)

	var reroll_btn = _make_btn("重铸 (%d金) - 重随一件装备的词缀数值" % REROLL_COST, Vector2(180, 120), _on_reroll)
	_panel.add_child(reroll_btn)

	var close_btn = _make_btn("关闭", Vector2(180, 240), _close_panel)
	_panel.add_child(close_btn)


func _make_btn(text: String, pos: Vector2, callback: Callable) -> Control:
	var btn = ColorRect.new()
	btn.size = Vector2(280, 30)
	btn.position = pos
	btn.color = Color(0.2, 0.2, 0.3, 0.8)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var lbl = Label.new()
	lbl.text = text
	lbl.position = Vector2(8, 5)
	lbl.size = Vector2(264, 20)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			callback.call()
	)
	return btn


func _on_reroll():
	var player = GameManager.player
	if not player:
		return
	var equip_mgr = player.get_node_or_null("EquipmentManager")
	if not equip_mgr:
		return
	var items = equip_mgr.get_all_equipped()
	if items.is_empty():
		_show_msg("没有已装备的物品")
		return
	var lobby_data = SaveSystem.load_lobby_data()
	if lobby_data.get("gold", 0) < REROLL_COST:
		_show_msg("金币不足! (%d金)" % REROLL_COST)
		return
	var target_slot = -1
	var target_item = null
	for slot in items.keys():
		var item = items[slot] as EquipmentBase
		if item and item.affixes.size() > 0:
			target_slot = slot
			target_item = item
			break
	if not target_item:
		_show_msg("没有带词缀的装备")
		return
	_reroll_item(target_item, lobby_data)
	equip_mgr.unequip(target_slot)
	equip_mgr.equip(target_item)
	_update_gold_label()
	_show_msg("重铸完成! 消耗 %d 金币" % REROLL_COST)


func _update_gold_label():
	if not _panel:
		return
	var title = _panel.get_node_or_null("Title")
	if title and title is Label:
		var lobby_data = SaveSystem.load_lobby_data()
		title.text = "附魔台  (金币: %d)" % lobby_data.get("gold", 0)


func _reroll_item(item, lobby_data):
	for aff in item.affixes:
		var rng = RarityTable.get_affix_level_range(item.rarity)
		aff.level = int(randf_range(rng.x, rng.y + 0.99))
		_recalc_affix_values(aff)
	lobby_data["gold"] = lobby_data.get("gold", 0) - REROLL_COST
	SaveSystem.save_lobby_data(lobby_data)


func _recalc_affix_values(aff: Affix):
	var mult = 1.0 + (aff.level - 1) * 0.25
	for m in aff.stat_modifiers:
		m.value = _base_affix_value(aff.affix_name, m.target_stat, m.modifier_type) * mult
	for e in aff.trigger_effects:
		e.param_value *= mult
	for c in aff.conditional_bonuses:
		if c.bonus:
			c.bonus.value = _base_affix_value(aff.affix_name, c.bonus.target_stat, c.bonus.modifier_type) * mult


func _base_affix_value(affix_name: String, target_stat: int, mod_type: int) -> float:
	var defs = AffixDatabase.get_all_affixes()
	for a in defs:
		if a.affix_name == affix_name:
			for m in a.stat_modifiers:
				if m.target_stat == target_stat and m.modifier_type == mod_type:
					return m.value
			for e in a.trigger_effects:
				return e.param_value
			for c in a.conditional_bonuses:
				if c.bonus:
					return c.bonus.value
	return 0.0


func _show_msg(text: String):
	if not _panel:
		return
	var existing = _panel.get_node_or_null("Msg")
	if existing:
		existing.queue_free()
	var msg = Label.new()
	msg.name = "Msg"
	msg.text = text
	msg.position = Vector2(180, 170)
	msg.size = Vector2(280, 40)
	msg.add_theme_font_size_override("font_size", 11)
	msg.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	_panel.add_child(msg)


func _close_panel():
	if _panel:
		_panel.queue_free()
		_panel = null
