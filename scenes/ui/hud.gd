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

func _ready():
	_build_bars()
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

	_update_hp(st.hp, st.max_hp, 0)
	_update_energy(st.energy, st.max_energy, 0)
	_update_stamina(st.stamina, st.max_stamina, 0)
	_update_heat(st.heat, st.max_heat, 0)

	player.weapon.weapon_changed.connect(_on_weapon_changed)
	if player.weapon.current_weapon:
		_on_weapon_changed(player.weapon.current_weapon)

func _update_hp(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("hp", current / max_v if max_v > 0 else 0)
	_bars.hp.label.text = "HP: %.0f/%.0f" % [current, max_v]

func _update_energy(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("energy", current / max_v if max_v > 0 else 0)
	_bars.energy.label.text = "能量: %.0f/%.0f" % [current, max_v]

func _update_stamina(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("stamina", current / max_v if max_v > 0 else 0)
	_bars.stamina.label.text = "体力: %.0f/%.0f" % [current, max_v]

func _update_heat(current: float, max_v: float, _delta: float):
	_apply_bar_ratio("heat", current / max_v if max_v > 0 else 0)
	_bars.heat.label.text = "热量: %.0f/%.0f" % [current, max_v]

func _apply_bar_ratio(key: String, ratio: float):
	if not _bars.has(key):
		return
	var b = _bars[key]
	b.fill.size.x = b.max_w * clamp(ratio, 0.0, 1.0)

func _on_weapon_changed(weapon: WeaponBase):
	var color = DamageSystem.get_color(weapon.damage_type)
	weapon_label.text = "武器: %s | 伤害: %.0f | 类型: %s" % [weapon.weapon_name, weapon.damage, DamageSystem.damage_type_to_string(weapon.damage_type)]
	weapon_label.add_theme_color_override("font_color", color)

func _on_damage_dealt(_attacker: Node2D, defender: Node2D, amount: float, _damage_type: int):
	if not is_instance_valid(defender):
		return
	var is_crit = false
	if defender.has_method("take_damage"):
		pass
	spawn_damage_number(defender.global_position, amount, is_crit)

func spawn_damage_number(world_pos: Vector2, amount: float, is_critical: bool = false):
	var label = Label.new()
	var cam = get_viewport().get_camera_2d()
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
