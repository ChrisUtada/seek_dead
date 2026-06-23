extends CanvasLayer

@onready var weapon_label: Label = $WeaponLabel

var _bars: Dictionary = {}
var _bar_order = ["hp", "energy", "stamina", "heat"]
var _bar_config = {
	hp = {color = Color(0.8, 0.15, 0.15), label = "HP"},
	energy = {color = Color(0.15, 0.3, 0.8), label = "能量"},
	stamina = {color = Color(0.15, 0.7, 0.15), label = "体力"},
	heat = {color = Color(0.9, 0.6, 0.1), label = "热量"},
}
var _crosshair: ColorRect
var _overlay: ColorRect
var _overlay_label: Label
var _overlay_button: Label
var _is_paused: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_bars()
	_build_crosshair()
	_build_overlay()
	_build_ammo_display()
	_build_skill_bar()
	_connect_player()
	EventManager.damage_dealt.connect(_on_damage_dealt)

func _build_bars():
	var y = 34
	var bar_w = 200
	var bar_h = 16
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
	_overlay.size = Vector2(800, 600)
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.name = "OverlayLabel"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.position = Vector2(0, 200)
	_overlay_label.size = Vector2(800, 80)
	_overlay_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_overlay_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_label.add_theme_constant_override("outline_size", 3)
	add_child(_overlay_label)

	_overlay_button = Label.new()
	_overlay_button.name = "OverlayButton"
	_overlay_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_button.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_button.position = Vector2(0, 300)
	_overlay_button.size = Vector2(800, 40)
	_overlay_button.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_overlay_button.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_button.add_theme_constant_override("outline_size", 2)
	add_child(_overlay_button)

func _connect_player():
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player:
		await get_tree().process_frame
		player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player:
		return

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

func _build_skill_bar():
	var skill_bar = Control.new()
	skill_bar.name = "SkillBar"
	skill_bar.position = Vector2(300, 550)
	skill_bar.size = Vector2(200, 40)
	add_child(skill_bar)
	var keys = ["Q", "E", "F", "C"]
	for i in range(4):
		var slot = ColorRect.new()
		slot.name = "SkillSlot%d" % i
		slot.position = Vector2(i * 50, 0)
		slot.size = Vector2(40, 40)
		slot.color = Color(0.3, 0.3, 0.3, 0.8)
		skill_bar.add_child(slot)
		var key_label = Label.new()
		key_label.text = keys[i]
		key_label.position = Vector2(14, 24)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1))
		key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		key_label.add_theme_constant_override("outline_size", 1)
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
	label.position = Vector2(10, 110)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 1)
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

func _on_skill_used(index: int, _skill: SkillBase):
	var slot = get_node_or_null("SkillBar/SkillSlot%d" % index)
	if not slot:
		return
	var cd = slot.get_node_or_null("Cooldown")
	if not cd:
		return
	var tween = create_tween()
	cd.size.y = 40
	tween.tween_property(cd, "size:y", 0, _skill.cooldown)

func _on_reload_finished():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 已装填"

func _on_weapon_changed(weapon: WeaponBase):
	var color = DamageSystem.get_color(weapon.damage_type)
	weapon_label.text = "武器: %s | 伤害: %.0f | 类型: %s" % [weapon.weapon_name, weapon.damage, DamageSystem.damage_type_to_string(weapon.damage_type)]
	weapon_label.add_theme_color_override("font_color", color)

func _on_player_died():
	_show_overlay("你死了", "按 F2 重新开始", Color(0.6, 0.1, 0.1, 0.7))

func _show_overlay(title: String, button_text: String, bg_color: Color):
	_overlay.color = bg_color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_label.text = title
	_overlay_button.text = button_text

func _hide_overlay():
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.text = ""
	_overlay_button.text = ""

func _input(event):
	if event.is_action_pressed("pause"):
		_toggle_pause()
	if event.is_action_pressed("restart") and _overlay.color.a > 0.5:
		get_tree().reload_current_scene()

func _toggle_pause():
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	if _is_paused:
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
	label.position -= Vector2(20, 0)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_critical else Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 2)
	label.text = "%.0f" % amount
	if is_critical:
		label.text = "暴击! " + label.text
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -40), 0.8)
	tween.parallel().tween_property(label, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(label.queue_free)

func _on_damage_dealt(_attacker: Node2D, defender: Node2D, amount: float, _damage_type: int):
	if not is_instance_valid(defender):
		return
	spawn_damage_number(defender.global_position, amount, false)
