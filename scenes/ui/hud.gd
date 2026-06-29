extends CanvasLayer

const _WeaponNode = preload("res://scripts/battle/weapon_node.gd")
const _EquipmentPanel = preload("res://scenes/ui/equipment_panel.gd")
const _ComparePopup = preload("res://scenes/ui/compare_popup.gd")

@onready var weapon_label: Label = $WeaponLabel

var _bars: Dictionary = {}
var _equipment_panel: EquipmentPanel = null
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

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_bars()
	_build_crosshair()
	_build_overlay()
	_build_hit_flash()
	_build_ammo_display()
	_build_skill_bar()
	_build_escape_bar()
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
	if player.weapon.current_weapon:
		_on_weapon_changed(player.weapon.current_weapon)

	var ammo_node = player.get_node_or_null("AmmoSystem")
	if ammo_node:
		ammo_node.ammo_changed.connect(_on_ammo_changed)
		ammo_node.reload_started.connect(_on_reload_started)
		ammo_node.reload_finished.connect(_on_reload_finished)
		_on_ammo_changed(ammo_node.current_ammo, ammo_node.max_ammo)

	var skill_node = player.get_node_or_null("SkillManager")
	if skill_node:
		skill_node.skill_used.connect(_on_skill_used)
		if skill_node.skills.size() > 2:
			var esc = skill_node.skills[2]
			if esc is EscapeSkill:
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

func _on_equipment_changed(_a = null, _b = null):
	if _equipment_panel and _equipment_panel.visible:
		_equipment_panel.refresh()

func _on_item_added(item: EquipmentBase, _index: int, player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if not mgr:
		return
	var equipped = mgr.get_equipped(item.slot) as EquipmentBase
	if not equipped:
		return
	call_deferred("_show_compare_popup", player, item)

func _show_compare_popup(player: Node2D, item: EquipmentBase):
	var popup = _ComparePopup.new()
	popup.name = "ComparePopup"
	add_child(popup)
	popup.init(player, item)

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


func _build_skill_bar():
	var skill_bar = Control.new()
	skill_bar.name = "SkillBar"
	skill_bar.position = Vector2(580, 324)
	skill_bar.size = Vector2(78, 24)
	add_child(skill_bar)
	var keys = ["Q", "E", "Z"]
	for i in range(3):
		var slot = ColorRect.new()
		slot.name = "SkillSlot%d" % i
		slot.position = Vector2(i * 26, 0)
		slot.size = Vector2(24, 24)
		slot.color = Color(0.3, 0.3, 0.3, 0.8)
		skill_bar.add_child(slot)
		var key_label = Label.new()
		key_label.text = keys[i]
		key_label.position = Vector2(7, 12)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1))
		key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		key_label.add_theme_constant_override("outline_size", 1)
		key_label.add_theme_font_size_override("font_size", 10)
		slot.add_child(key_label)
		var cd_overlay = ColorRect.new()
		cd_overlay.name = "Cooldown"
		cd_overlay.position = Vector2(0, 0)
		cd_overlay.size = Vector2(40, 0)
		cd_overlay.color = Color(0, 0, 0, 0.7)
		slot.add_child(cd_overlay)

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
	var slot = get_node_or_null("SkillBar/SkillSlot2")
	if slot:
		var cd = slot.get_node_or_null("Cooldown")
		if cd:
			var tween = create_tween()
			cd.size.y = 40
			tween.tween_property(cd, "size:y", 0, 90.0)


func _on_skill_used(index: int, _skill: SkillBase):
	var slot = get_node_or_null("SkillBar/SkillSlot%d" % index)
	if not slot:
		return
	var cd = slot.get_node_or_null("Cooldown")
	if not cd:
		return
	if index == 2:
		return
	var tween = create_tween()
	cd.size.y = 40
	tween.tween_property(cd, "size:y", 0, _skill.cooldown)

func _on_reload_finished():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 已装填"

func _on_weapon_changed(weapon: WeaponNode):
	var s = weapon.stats
	if not s:
		return
	var color = DamageSystem.get_color(s.damage_type)
	weapon_label.text = "武器: %s | 伤害: %.0f | 类型: %s" % [s.weapon_name, s.damage, DamageSystem.damage_type_to_string(s.damage_type)]
	weapon_label.add_theme_color_override("font_color", color)

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
