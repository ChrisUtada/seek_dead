extends CanvasLayer

const _WeaponNode = preload("res://scripts/battle/weapon_node.gd")
const _EquipmentPanel = preload("res://scenes/ui/equipment_panel.gd")

@onready var weapon_label: Label = $WeaponLabel

var _bars: Dictionary = {}
var _equipment_panel: EquipmentPanel = null
var _skill_manager: SkillManager
var _skill_slots: Array = []
var _escape_btn: ColorRect = null
var _lobby_btn: ColorRect = null
var _bar_order = ["hp", "energy", "stamina", "heat"]
var _bar_config = {
	hp = {color = Color(0.8, 0.15, 0.15), label = "HP"},
	energy = {color = Color(0.15, 0.3, 0.8), label = "能量"},
	stamina = {color = Color(0.15, 0.7, 0.15), label = "体力"},
	heat = {color = Color(0.9, 0.6, 0.1), label = "热量"},
}
var _crosshair: ColorRect
var _overlay: ColorRect
var _flash_overlay: ColorRect
var _overlay_label: Label
var _overlay_button: Label
var _is_paused: bool = false
var _death_overlay: bool = false

var _choice_panel: Control = null
var _choice_card_rects: Array = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_bars()
	_build_crosshair()
	_build_overlay()
	_build_hit_flash()
	_build_ammo_display()
	_build_skill_bar()
	_build_escape_bar()
	_build_utility_bar()
	_connect_player()
	EventManager.damage_dealt.connect(_on_damage_dealt)

func _build_bars():
	var y = 8
	var bar_w = 180
	var bar_h = 12
	var gap = 4
	for key in _bar_order:
		var cfg = _bar_config[key]
		var bg = ColorRect.new()
		bg.name = key.to_upper() + "Bg"
		bg.position = Vector2(10, y)
		bg.size = Vector2(bar_w, bar_h)
		bg.color = Color(0.15, 0.15, 0.15, 0.8)
		add_child(bg)
		var fill = ColorRect.new()
		fill.name = key.to_upper() + "Fill"
		fill.position = Vector2(10, y)
		fill.size = Vector2(bar_w, bar_h)
		fill.color = cfg.color
		add_child(fill)
		var label = Label.new()
		label.name = key.to_upper() + "Label"
		label.position = Vector2(14, y)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 1)
		label.add_theme_font_size_override("font_size", 11)
		label.text = "%s: --/--" % cfg.label
		add_child(label)
		_bars[key] = {bg = bg, fill = fill, label = label, max_w = bar_w}
		_apply_bar_ratio(key, 1.0)
		y += bar_h + gap

func _build_crosshair():
	_crosshair = ColorRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.size = Vector2(8, 8)
	_crosshair.color = Color(1, 1, 1, 0.7)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

func _build_overlay():
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.size = Vector2(640, 360)
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.name = "OverlayLabel"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.position = Vector2(0, 130)
	_overlay_label.size = Vector2(640, 40)
	_overlay_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_overlay_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_label.add_theme_constant_override("outline_size", 3)
	_overlay_label.add_theme_font_size_override("font_size", 22)
	add_child(_overlay_label)

	_flash_overlay = ColorRect.new()
	_flash_overlay.name = "FlashOverlay"
	_flash_overlay.size = Vector2(640, 360)
	_flash_overlay.color = Color(0, 0, 0, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_overlay)

	_overlay_button = Label.new()
	_overlay_button.name = "OverlayButton"
	_overlay_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_button.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_button.position = Vector2(0, 180)
	_overlay_button.size = Vector2(640, 20)
	_overlay_button.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_overlay_button.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_button.add_theme_constant_override("outline_size", 2)
	_overlay_button.add_theme_font_size_override("font_size", 14)
	add_child(_overlay_button)

func _connect_player():
	var player: Node2D = null
	while player == null:
		player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
		if player == null:
			await get_tree().process_frame

	var st = player.state
	st.hp_changed.connect(_update_hp)
	st.energy_changed.connect(_update_energy)
	st.stamina_changed.connect(_update_stamina)
	st.heat_changed.connect(_update_heat)
	st.died.connect(_on_player_died)
	st.stamina_low.connect(_on_stamina_low)
	st.stamina_depleted.connect(_on_stamina_depleted)
	st.heat_warning.connect(_on_heat_warning)
	st.meltdown_triggered.connect(_on_meltdown_triggered)
	st.meltdown_ended.connect(_on_meltdown_ended)
	_update_hp(st.hp, st.max_hp, 0)
	_update_energy(st.energy, st.max_energy, 0)
	_update_stamina(st.stamina, st.max_stamina, 0)
	_update_heat(st.heat, st.max_heat, 0)

	player.weapon.weapon_changed.connect(_on_weapon_changed)
	player.weapon.active_hand_changed.connect(_on_active_hand_changed)
	var active_node = player.weapon.get_active_weapon_node()
	if active_node:
		_on_weapon_changed(active_node, player.weapon.active_hand)

	var ammo_node = player.get_node_or_null("AmmoSystem")
	if ammo_node:
		ammo_node.ammo_changed.connect(_on_ammo_changed)
		ammo_node.reload_started.connect(_on_reload_started)
		ammo_node.reload_finished.connect(_on_reload_finished)
		_on_ammo_changed(ammo_node.current_ammo, ammo_node.max_ammo)

	var skill_node = player.get_node_or_null("SkillManager")
	if skill_node:
		_skill_manager = skill_node
		skill_node.skill_used.connect(_on_skill_used)
		skill_node.skill_added.connect(_on_skill_added)
		skill_node.skill_removed.connect(_on_skill_removed)
		skill_node.skill_upgraded.connect(_on_skill_upgraded)
		skill_node.skill_replace_needed.connect(_on_skill_replace_needed)

	if "escape_skill" in player and player.escape_skill:
		var esc = player.escape_skill
		esc.channel_started.connect(_on_escape_channel_started)
		esc.channel_progress.connect(_on_escape_channel_progress)
		esc.channel_cancelled.connect(_on_escape_channel_cancelled)
		esc.channel_completed.connect(_on_escape_channel_completed)

	_init_equipment_panel(player)
	_connect_equipment_signals(player)

func _init_equipment_panel(player: Node2D):
	_equipment_panel = _EquipmentPanel.new()
	_equipment_panel.name = "EquipmentPanel"
	_equipment_panel.hide()
	add_child(_equipment_panel)
	_equipment_panel.init(player)


func _connect_equipment_signals(player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if mgr:
		mgr.equipment_equipped.connect(_on_equipment_changed)
		mgr.equipment_unequipped.connect(_on_equipment_changed)
		mgr.trigger_activated.connect(_on_trigger_activated.bind(player))
		var set_mgr = mgr.get_node_or_null("SetBonusManager") as SetBonusManager
		if set_mgr:
			set_mgr.set_bonus_activated.connect(_on_set_bonus_activated.bind(player))
	var inv = player.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if inv:
		inv.inventory_changed.connect(_on_equipment_changed)
		inv.item_added.connect(_on_item_added.bind(player))
		inv.item_removed.connect(_on_item_removed)

func _on_item_removed(item: EquipmentBase, _index: int):
	print("[丢弃] %s" % item.equipment_name)

func _on_equipment_changed(_a = null, _b = null):
	if _equipment_panel and _equipment_panel.visible:
		_equipment_panel.refresh()

func _on_item_added(item: EquipmentBase, index: int, player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if not mgr:
		return
	if mgr.get_equipped(item.slot) != null:
		print("[拾取→背包] %s (槽位已被占)" % item.equipment_name)
		return
	var inv = player.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if not inv:
		return
	inv.remove_item(index)
	mgr.equip(item)
	print("[拾取→装备] %s" % item.equipment_name)

func _update_hp(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("hp", current / max_v if max_v > 0 else 0)
	_bars.hp.label.text = "HP: %.0f/%.0f" % [current, max_v]

func _update_energy(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("energy", current / max_v if max_v > 0 else 0)
	_bars.energy.label.text = "能量: %.0f/%.0f" % [current, max_v]

func _update_stamina(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("stamina", current / max_v if max_v > 0 else 0)
	_bars.stamina.label.text = "体力: %.0f/%.0f" % [current, max_v]

func _on_stamina_low():
	var fill = _bars.stamina.fill
	var tween = create_tween().set_loops(4)
	tween.tween_property(fill, "color", Color(1, 0, 0), 0.15)
	tween.tween_property(fill, "color", Color(0.15, 0.7, 0.15), 0.15)

func _on_stamina_depleted():
	var fill = _bars.stamina.fill
	var tween = create_tween()
	tween.tween_property(fill, "color", Color(1, 0.3, 0.3), 0.2)
	tween.tween_property(fill, "color", Color(0.15, 0.7, 0.15), 0.5)

func _on_heat_warning():
	var fill = _bars.heat.fill
	var tween = create_tween().set_loops(6)
	tween.tween_property(fill, "color", Color(1, 0.8, 0.1), 0.15)
	tween.tween_property(fill, "color", Color(0.9, 0.6, 0.1), 0.15)

func _on_meltdown_triggered():
	var fill = _bars.heat.fill
	fill.color = Color(1, 0.9, 0.1)
	_bars.heat.label.text = "热量: 超载中!"
	var pulse = create_tween().set_loops()
	pulse.tween_property(fill, "color", Color(1, 0.4, 0.1), 0.3)
	pulse.tween_property(fill, "color", Color(1, 0.9, 0.1), 0.3)

func _on_meltdown_ended():
	var fill = _bars.heat.fill
	fill.color = Color(0.9, 0.6, 0.1)
	_bars.heat.label.text = "热量: 0%"

func _update_heat(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("heat", current / max_v if max_v > 0 else 0)
	_bars.heat.label.text = "热量: %.0f/%.0f" % [current, max_v]

func _apply_bar_ratio(key: String, ratio: float):
	if not _bars.has(key):
		return
	var target_w = _bars[key].max_w * clamp(ratio, 0.0, 1.0)
	var bar = _bars[key].fill
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bar, "size:x", target_w, 0.25)

func _build_escape_bar():
	var bg = ColorRect.new()
	bg.name = "EscapeBarBg"
	bg.position = Vector2(220, 200)
	bg.size = Vector2(200, 16)
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.visible = false
	add_child(bg)
	var fill = ColorRect.new()
	fill.name = "EscapeBarFill"
	fill.position = Vector2(0, 0)
	fill.size = Vector2(0, 16)
	fill.color = Color(1, 0.7, 0.1, 0.9)
	bg.add_child(fill)
	var label = Label.new()
	label.name = "EscapeBarLabel"
	label.position = Vector2(0, 0)
	label.size = Vector2(200, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "撤离中...  再次按Z取消"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 10)
	bg.add_child(label)


func _build_utility_bar():
	var start_x = 364
	var y = 324
	var sz = Vector2(28, 28)
	var gap = 4

	_escape_btn = ColorRect.new()
	_escape_btn.name = "EscapeBtn"
	_escape_btn.position = Vector2(start_x, y)
	_escape_btn.size = sz
	_escape_btn.color = Color(0.25, 0.25, 0.25, 0.85)
	add_child(_escape_btn)
	var zkey = Label.new()
	zkey.text = "Z"
	zkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zkey.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	zkey.position = Vector2(2, 1)
	zkey.size = Vector2(sz.x - 4, 12)
	zkey.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	zkey.add_theme_constant_override("outline_size", 1)
	zkey.add_theme_font_size_override("font_size", 8)
	_escape_btn.add_child(zkey)
	var zname = Label.new()
	zname.name = "EscapeName"
	zname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zname.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	zname.position = Vector2(0, 0)
	zname.size = sz
	zname.add_theme_color_override("font_color", Color(1, 1, 1))
	zname.add_theme_constant_override("outline_size", 1)
	zname.add_theme_font_size_override("font_size", 7)
	zname.text = "撤离"
	_escape_btn.add_child(zname)
	var zcd = ColorRect.new()
	zcd.name = "EscapeCD"
	zcd.position = Vector2(0, 0)
	zcd.size = Vector2(sz.x, 0)
	zcd.color = Color(0, 0, 0, 0.75)
	_escape_btn.add_child(zcd)

	_lobby_btn = ColorRect.new()
	_lobby_btn.name = "LobbyBtn"
	_lobby_btn.position = Vector2(start_x + sz.x + gap, y)
	_lobby_btn.size = sz
	_lobby_btn.color = Color(0.2, 0.2, 0.25, 0.85)
	add_child(_lobby_btn)
	var ukey = Label.new()
	ukey.text = "U"
	ukey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ukey.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ukey.position = Vector2(2, 1)
	ukey.size = Vector2(sz.x - 4, 12)
	ukey.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ukey.add_theme_constant_override("outline_size", 1)
	ukey.add_theme_font_size_override("font_size", 8)
	_lobby_btn.add_child(ukey)
	var uname = Label.new()
	uname.text = "返回"
	uname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	uname.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	uname.position = Vector2(0, 0)
	uname.size = sz
	uname.add_theme_color_override("font_color", Color(1, 1, 1))
	uname.add_theme_constant_override("outline_size", 1)
	uname.add_theme_font_size_override("font_size", 7)
	_lobby_btn.add_child(uname)


func _build_skill_bar():
	var skill_bar = Control.new()
	skill_bar.name = "SkillBar"
	skill_bar.position = Vector2(272, 324)
	skill_bar.size = Vector2(68, 32)
	add_child(skill_bar)
	var slot_size = 32
	var gap = 4
	for i in range(2):
		var slot = ColorRect.new()
		slot.name = "SkillSlot%d" % i
		slot.position = Vector2(i * (slot_size + gap), 0)
		slot.size = Vector2(slot_size, slot_size)
		slot.color = Color(0.25, 0.25, 0.25, 0.85)
		skill_bar.add_child(slot)
		var key_label = Label.new()
		key_label.text = str(i + 1)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		key_label.position = Vector2(0, 0)
		key_label.size = Vector2(slot_size, slot_size)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		key_label.add_theme_constant_override("outline_size", 1)
		key_label.add_theme_font_size_override("font_size", 9)
		slot.add_child(key_label)
		var name_label = Label.new()
		name_label.name = "SkillName"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.position = Vector2(0, 0)
		name_label.size = Vector2(slot_size, slot_size)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1))
		name_label.add_theme_constant_override("outline_size", 1)
		name_label.add_theme_font_size_override("font_size", 10)
		slot.add_child(name_label)
		var level_label = Label.new()
		level_label.name = "Level"
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		level_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		level_label.position = Vector2(0, 0)
		level_label.size = Vector2(slot_size - 1, slot_size - 1)
		level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
		level_label.add_theme_constant_override("outline_size", 1)
		level_label.add_theme_font_size_override("font_size", 8)
		slot.add_child(level_label)
		var cd_overlay = ColorRect.new()
		cd_overlay.name = "Cooldown"
		cd_overlay.position = Vector2(0, 0)
		cd_overlay.size = Vector2(slot_size, 0)
		cd_overlay.color = Color(0, 0, 0, 0.75)
		slot.add_child(cd_overlay)
		_skill_slots.append(slot)

func _build_ammo_display():
	var label = Label.new()
	label.name = "AmmoLabel"
	label.position = Vector2(10, 76)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 10)
	label.text = "弹药: --/--"
	add_child(label)
	_bars["ammo"] = {label = label}

func _on_ammo_changed(current: int, max_cap: int):
	if not _bars.has("ammo"):
		return
	_bars.ammo.label.text = "弹药: %d/%d" % [current, max_cap]
	if max_cap > 0 and float(current) / float(max_cap) < 0.25:
		_bars.ammo.label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		_bars.ammo.label.add_theme_color_override("font_color", Color(1, 1, 1))

func _on_reload_started():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 装弹中..."

func _on_escape_channel_started(_duration: float):
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = true
		bg.get_node("EscapeBarFill").size.x = 0


func _on_escape_channel_progress(ratio: float):
	var fill = get_node_or_null("EscapeBarBg/EscapeBarFill")
	if fill:
		fill.size.x = 200 * ratio


func _on_escape_channel_cancelled():
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = false
		bg.get_node("EscapeBarFill").size.x = 0


func _on_escape_channel_completed():
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = false
		bg.get_node("EscapeBarFill").size.x = 0


func _on_skill_used(_index: int, _skill: SkillBase):
	pass

func _on_skill_added(_skill: SkillBase):
	pass

func _on_skill_removed(_skill: SkillBase):
	pass


func _on_skill_upgraded(skill: SkillBase, old_level: int, new_level: int):
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player:
		return
	var text = "%s +1 Lv.%d!" % [skill.skill_name, new_level]
	spawn_floating_text(player.global_position, text, Color(0.3, 1, 0.3))


var _replace_popup: Control = null
var _pending_skill: SkillBase = null


func _on_skill_replace_needed(new_skill: SkillBase):
	if _replace_popup:
		return
	_pending_skill = new_skill
	_replace_popup = Control.new()
	_replace_popup.name = "ReplacePopup"
	_replace_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 4)
	_replace_popup.size = Vector2(220, 100)
	add_child(_replace_popup)

	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.9)
	bg.size = Vector2(220, 100)
	_replace_popup.add_child(bg)

	var title = Label.new()
	title.text = "技能替换"
	title.position = Vector2(8, 4)
	title.size = Vector2(200, 16)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 12)
	_replace_popup.add_child(title)

	var prompt = Label.new()
	prompt.text = "选择要替换的技能："
	prompt.position = Vector2(8, 20)
	prompt.size = Vector2(200, 14)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	prompt.add_theme_font_size_override("font_size", 10)
	_replace_popup.add_child(prompt)

	var slot_size = 36
	var gap = 4
	var start_x = 8
	for i in range(_skill_manager.skills.size()):
		var btn = ColorRect.new()
		btn.name = "SlotBtn%d" % i
		btn.position = Vector2(start_x + i * (slot_size + gap), 38)
		btn.size = Vector2(slot_size, slot_size)
		btn.color = Color(0.3, 0.3, 0.5, 0.9)
		_replace_popup.add_child(btn)

		var lbl = Label.new()
		lbl.text = _skill_manager.skills[i].skill_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(0, 0)
		lbl.size = Vector2(slot_size, slot_size)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 9)
		btn.add_child(lbl)

		var lv = Label.new()
		lv.text = "Lv%d" % _skill_manager.skills[i].level
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lv.position = Vector2(0, 0)
		lv.size = Vector2(slot_size - 1, slot_size - 1)
		lv.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
		lv.add_theme_font_size_override("font_size", 8)
		btn.add_child(lv)

		var click_area = Area2D.new()
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(slot_size, slot_size)
		shape.shape = rect
		click_area.add_child(shape)
		click_area.global_position = btn.global_position + btn.size / 2
		var idx = i
		click_area.input_event.connect(func(_v, _e, _i): _on_replace_confirm(idx))
		_replace_popup.add_child(click_area)
		click_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var discard_btn = ColorRect.new()
	discard_btn.name = "DiscardBtn"
	discard_btn.position = Vector2(start_x + _skill_manager.skills.size() * (slot_size + gap), 38)
	discard_btn.size = Vector2(slot_size, slot_size)
	discard_btn.color = Color(0.5, 0.3, 0.3, 0.9)
	_replace_popup.add_child(discard_btn)

	var discard_lbl = Label.new()
	discard_lbl.text = "放弃"
	discard_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discard_lbl.position = Vector2(0, 0)
	discard_lbl.size = Vector2(slot_size, slot_size)
	discard_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	discard_lbl.add_theme_font_size_override("font_size", 9)
	discard_btn.add_child(discard_lbl)

	var discard_click = Area2D.new()
	var dshape = CollisionShape2D.new()
	var drect = RectangleShape2D.new()
	drect.size = Vector2(slot_size, slot_size)
	dshape.shape = drect
	discard_click.add_child(dshape)
	discard_click.input_event.connect(func(_v, _e, _i): _on_replace_discard())
	_replace_popup.add_child(discard_click)


func _close_replace_popup():
	if _replace_popup:
		_replace_popup.queue_free()
		_replace_popup = null
	_pending_skill = null


func _on_replace_confirm(index: int):
	if not _pending_skill or not _skill_manager:
		_close_replace_popup()
		return
	_skill_manager.replace_skill(index, _pending_skill.duplicate(true))
	print("[技能替换] 槽%d → %s" % [index, _pending_skill.skill_name])
	_close_replace_popup()


func _on_replace_discard():
	print("[技能替换] 放弃拾取: %s" % [_pending_skill.skill_name if _pending_skill else "null"])
	_close_replace_popup()

func _on_reload_finished():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 已装填"

func _on_weapon_changed(weapon: WeaponNode, _hand: int = 0):
	var s = weapon.weapon_data
	if not s:
		return
	var hand_label = "主手" if _hand == 0 else "副手"
	var color = DamageSystem.get_color(s.damage_type)
	weapon_label.text = "%s | %s | 伤害: %.0f | 类型: %s" % [hand_label, s.weapon_name, s.damage, DamageSystem.damage_type_to_string(s.damage_type)]
	weapon_label.add_theme_color_override("font_color", color)

func _on_active_hand_changed(hand: int):
	var wc = EntityRegistry.players[0].weapon as WeaponComponent
	if not wc:
		return
	var node = wc.get_active_weapon_node()
	if node:
		_on_weapon_changed(node, hand)
	else:
		weapon_label.text = ""

func _on_player_died():
	_death_overlay = true
	_show_overlay("你死了", "按 F2 重新开始", Color(0.6, 0.1, 0.1, 0.7))

func _show_overlay(title: String, button_text: String, bg_color: Color):
	_overlay.color = bg_color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_label.text = title
	_overlay_button.text = button_text

func _hide_overlay():
	_death_overlay = false
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.text = ""
	_overlay_button.text = ""

func _input(event):
	if event.is_action_pressed("pause"):
		_toggle_pause()
	if event.is_action_pressed("restart") and _death_overlay:
		call_deferred("_restart_game")
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
	if event.is_action_pressed("return_lobby") and not _is_paused and not _death_overlay:
		_return_to_lobby()
	if _choice_panel and not _choice_card_rects.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse = get_viewport().get_mouse_position()
		for entry in _choice_card_rects:
			var pos = _choice_panel.position + entry.rect.position
			if mouse.x >= pos.x and mouse.x <= pos.x + entry.rect.size.x and mouse.y >= pos.y and mouse.y <= pos.y + entry.rect.size.y:
				if _choice_panel.name == "SkillUpgradePanel":
					_on_skill_upgrade_selected(entry.skill)
				else:
					_on_skill_choice_selected(entry.skill)
				return

func _toggle_inventory():
	if not _equipment_panel:
		return
	_equipment_panel.visible = not _equipment_panel.visible
	if _equipment_panel.visible:
		_equipment_panel.refresh()

func _return_to_lobby():
	get_tree().paused = false
	SceneManager.fade_to_scene("res://scenes/ui/lobby.tscn")

func _restart_game():
	_return_to_lobby()

func _toggle_pause():
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	if _is_paused:
		AudioManager.play_sfx(AudioManager.SfxType.UI_PAUSE)
		_show_overlay("暂停", "按 Esc 继续", Color(0, 0, 0, 0.5))
	else:
		_hide_overlay()

func _process(_delta):
	var mouse = get_viewport().get_mouse_position()
	_crosshair.position = mouse - _crosshair.size / 2
	_update_skill_bar()
	_update_utility_bar()


func _update_skill_bar():
	if not _skill_manager or _skill_slots.size() == 0:
		return
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	var state = player.state if player and player.state else null
	for i in range(min(_skill_slots.size(), _skill_manager.skills.size())):
		var skill = _skill_manager.skills[i]
		var slot = _skill_slots[i]
		var cd = slot.get_node_or_null("Cooldown")
		if cd:
			var ratio = skill.get_cooldown_ratio()
			cd.size.y = slot.size.y * ratio
		var name_label = slot.get_node_or_null("SkillName")
		if name_label:
			name_label.text = skill.skill_name
		var level_label = slot.get_node_or_null("Level")
		if level_label:
			level_label.text = "Lv%d" % skill.level if skill.level > 0 else ""
		if state and not skill.can_use(state):
			slot.color = Color(0.15, 0.15, 0.15, 0.85)
		else:
			slot.color = Color(0.25, 0.25, 0.25, 0.85)

func spawn_damage_number(world_pos: Vector2, amount: float, is_critical: bool = false):
	var label = Label.new()
	var viewport = get_viewport()
	if not viewport:
		return
	var cam = viewport.get_camera_2d()
	if cam:
		label.position = cam.get_canvas_transform() * world_pos
	label.position -= Vector2(8, 0)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_critical else Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 16)
	label.text = "%.0f" % amount
	if is_critical:
		label.text = "暴击! " + label.text
	add_child(label)
	var tween = create_tween()
	var end_pos = label.position + Vector2(0, -30)
	if is_critical:
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
		end_pos = label.position + Vector2(0, -36)
	tween.tween_property(label, "position", end_pos, 0.8)
	tween.parallel().tween_property(label, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(label.queue_free)

func _on_trigger_activated(event: int, effect: TriggerEffect, player: Node2D):
	if not is_instance_valid(player):
		return
	var text = _trigger_floating_text(effect.effect_action)
	if text.length() == 0:
		return
	spawn_floating_text(player.global_position, text, _trigger_color(effect.effect_action))

func _on_set_bonus_activated(set_id: String, tier: int, player: Node2D):
	if not is_instance_valid(player):
		return
	var set_def = SetDatabase.get_set(set_id)
	if not set_def:
		return
	var text = "套装 %s %d件 已激活!" % [set_def.set_name, tier]
	spawn_floating_text(player.global_position, text, Color(0.3, 1, 0.3))

func _trigger_floating_text(action: int) -> String:
	match action:
		EquipmentEnums.EffectAction.EXPLODE: return "爆炸!"
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE: return "弹射!"
		EquipmentEnums.EffectAction.SPAWN_POOL: return "毒池!"
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING: return "连锁闪电!"
		EquipmentEnums.EffectAction.HEAL: return "回血!"
		EquipmentEnums.EffectAction.SHIELD: return "护盾!"
		EquipmentEnums.EffectAction.FIRE_AURA: return "火焰光环!"
		EquipmentEnums.EffectAction.KNOCKBACK: return "击退!"
		EquipmentEnums.EffectAction.SLOW_ENEMIES: return "减速!"
		_: return ""

func _trigger_color(action: int) -> Color:
	match action:
		EquipmentEnums.EffectAction.EXPLODE: return Color(1, 0.6, 0.1)
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE: return Color(0.6, 0.8, 1)
		EquipmentEnums.EffectAction.SPAWN_POOL: return Color(0.3, 1, 0.3)
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING: return Color(0.5, 0.5, 1)
		EquipmentEnums.EffectAction.HEAL: return Color(0.3, 1, 0.3)
		EquipmentEnums.EffectAction.SHIELD: return Color(0.3, 0.6, 1)
		EquipmentEnums.EffectAction.FIRE_AURA: return Color(1, 0.4, 0.1)
		EquipmentEnums.EffectAction.KNOCKBACK: return Color(1, 1, 0.3)
		EquipmentEnums.EffectAction.SLOW_ENEMIES: return Color(0.5, 0.8, 1)
		_: return Color.WHITE

func spawn_floating_text(world_pos: Vector2, text: String, color: Color = Color.WHITE):
	var label = Label.new()
	var viewport = get_viewport()
	if not viewport:
		return
	var cam = viewport.get_camera_2d()
	if cam:
		label.position = cam.get_canvas_transform() * world_pos
	label.position -= Vector2(30, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 14)
	label.text = text
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -40), 1.0)
	tween.parallel().tween_property(label, "modulate", Color(color.r, color.g, color.b, 0), 1.0)
	tween.tween_callback(label.queue_free)

func _build_hit_flash():
	pass

func _trigger_hit_flash(intensity: float = 0.08, color: Color = Color(1, 0.3, 0.3)):
	_flash_overlay.color = Color(color.r, color.g, color.b, intensity)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(_flash_overlay, "color", Color(color.r, color.g, color.b, 0), 0.08)

func _on_damage_dealt(attacker: Node2D, defender: Node2D, amount: float, _damage_type: int):
	if not is_instance_valid(defender):
		return
	spawn_damage_number(defender.global_position, amount, false)
	if defender.is_in_group("players"):
		_trigger_hit_flash(0.08, Color(1, 0.3, 0.3))
	elif amount > 50.0:
		_trigger_hit_flash(0.06, Color(1, 0.8, 0.3))


func show_skill_upgrade(sm: SkillManager):
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	get_tree().paused = true
	_choice_panel = Control.new()
	_choice_panel.name = "SkillUpgradePanel"
	var panel_w = 260
	var panel_h = 40 + sm.skills.size() * 70
	_choice_panel.size = Vector2(panel_w, panel_h)
	var viewport_size = get_viewport().get_visible_rect().size
	_choice_panel.position = (viewport_size - _choice_panel.size) / 2
	add_child(_choice_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.size = Vector2(panel_w, panel_h)
	_choice_panel.add_child(bg)

	var title = Label.new()
	title.text = "选择升级技能"
	title.position = Vector2(panel_w / 2 - 60, 8)
	title.size = Vector2(120, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 14)
	_choice_panel.add_child(title)

	var card_size = Vector2(panel_w - 24, 56)
	var start_y = 34
	_choice_card_rects.clear()
	for i in range(sm.skills.size()):
		var sk = sm.skills[i]
		var card = ColorRect.new()
		card.name = "UpgradeCard%d" % i
		card.position = Vector2(12, start_y + i * (int(card_size.y) + 8))
		card.size = card_size
		card.color = Color(0.2, 0.3, 0.25, 0.95) if sk.level < sk.max_level else Color(0.25, 0.2, 0.2, 0.95)
		_choice_panel.add_child(card)

		_choice_card_rects.append({rect = Rect2(card.position, card_size), skill = sk})

		var name_lbl = Label.new()
		name_lbl.text = sk.skill_name + "  Lv." + str(sk.level)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(0, 4)
		name_lbl.size = Vector2(card_size.x, 24)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.add_theme_font_size_override("font_size", 13)
		card.add_child(name_lbl)

		var status_lbl = Label.new()
		if sk.level >= sk.max_level:
			status_lbl.text = "已达最高等级"
			status_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		else:
			status_lbl.text = "点击升级至 Lv." + str(sk.level + 1)
			status_lbl.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.position = Vector2(0, 30)
		status_lbl.size = Vector2(card_size.x, 20)
		status_lbl.add_theme_font_size_override("font_size", 10)
		card.add_child(status_lbl)


func show_skill_choice(choices: Array[SkillBase]):
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	get_tree().paused = true
	_choice_panel = Control.new()
	_choice_panel.name = "SkillChoicePanel"
	_choice_panel.size = Vector2(400, 160)
	var viewport_size = get_viewport().get_visible_rect().size
	_choice_panel.position = (viewport_size - _choice_panel.size) / 2
	add_child(_choice_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.size = Vector2(400, 160)
	_choice_panel.add_child(bg)

	var title = Label.new()
	title.text = "选择技能"
	title.position = Vector2(140, 8)
	title.size = Vector2(120, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 14)
	_choice_panel.add_child(title)

	var card_size = Vector2(110, 120)
	var gap = 12
	var total_w = choices.size() * int(card_size.x) + (choices.size() - 1) * gap
	var start_x = (400 - total_w) / 2
	_choice_card_rects.clear()
	for i in range(choices.size()):
		var sk = choices[i]
		var card = ColorRect.new()
		card.name = "Card%d" % i
		card.position = Vector2(start_x + i * (int(card_size.x) + gap), 32)
		card.size = card_size
		card.color = Color(0.2, 0.2, 0.3, 0.95)
		_choice_panel.add_child(card)

		_choice_card_rects.append({rect = Rect2(card.position, card_size), skill = sk})

		var name_lbl = Label.new()
		name_lbl.text = sk.skill_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(0, 4)
		name_lbl.size = Vector2(card_size.x, 20)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.add_theme_font_size_override("font_size", 12)
		card.add_child(name_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = sk.skill_description
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.position = Vector2(4, 24)
		desc_lbl.size = Vector2(card_size.x - 8, 60)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(desc_lbl)

		var cost_lbl = Label.new()
		cost_lbl.text = "能量 %d  CD %.1fs" % [sk.energy_cost, sk.cooldown]
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cost_lbl.position = Vector2(0, card_size.y - 24)
		cost_lbl.size = Vector2(card_size.x, 20)
		cost_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1))
		cost_lbl.add_theme_font_size_override("font_size", 8)
		card.add_child(cost_lbl)


func _on_skill_upgrade_selected(skill: SkillBase):
	if not _skill_manager:
		_close_skill_choice()
		return
	for existing in _skill_manager.skills:
		if existing.skill_name == skill.skill_name:
			var old = existing.level
			existing.level += 1
			_skill_manager.skill_upgraded.emit(existing, old, existing.level)
			print("[技能升级] %s: Lv.%d → Lv.%d" % [existing.skill_name, old, existing.level])
			break
	_close_skill_choice()


func _on_skill_choice_selected(skill: SkillBase):
	if not _skill_manager:
		_close_skill_choice()
		return
	var dup = skill.duplicate(true)
	if _skill_manager.add_or_upgrade(dup):
		print("[技能选择] 选中: %s (Lv.%d)" % [dup.skill_name, dup.level])
	_close_skill_choice()


func _close_skill_choice():
	get_tree().paused = false
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	_choice_card_rects.clear()


func _update_utility_bar():
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player or not _escape_btn or not _lobby_btn:
		return

	if "escape_skill" in player and player.escape_skill:
		var esc = player.escape_skill
		var cd = _escape_btn.get_node_or_null("EscapeCD")
		if cd:
			var ratio = esc.cooldown_timer / esc.cooldown if esc.cooldown > 0 else 0
			cd.size.y = _escape_btn.size.y * ratio
		if esc.get("_is_channeling"):
			_escape_btn.color = Color(0.8, 0.6, 0.1, 0.85)
		elif esc.cooldown_timer > 0:
			_escape_btn.color = Color(0.25, 0.2, 0.2, 0.85)
		else:
			_escape_btn.color = Color(0.2, 0.5, 0.2, 0.85)

	_lobby_btn.color = Color(0.2, 0.2, 0.25, 0.85) if not get_tree().paused else Color(0.15, 0.15, 0.15, 0.85)
