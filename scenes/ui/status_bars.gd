class_name StatusBars
extends Node
## 玩家状态条（HP / 能量 / 体力 / 热量）及对应告警、熔毁动画。
## 由 HUD 在 _ready 中实例化并 add_child；connect_player() 注入玩家状态后自动更新。

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


## 注入玩家状态并连接所有数值/告警信号（注意：died 由 HUD 处理死亡覆盖层，不在此处）。
func connect_player(st):
	st.hp_changed.connect(_update_hp)
	st.energy_changed.connect(_update_energy)
	st.stamina_changed.connect(_update_stamina)
	st.heat_changed.connect(_update_heat)
	st.stamina_low.connect(_on_stamina_low)
	st.stamina_depleted.connect(_on_stamina_depleted)
	st.heat_warning.connect(_on_heat_warning)
	st.meltdown_triggered.connect(_on_meltdown_triggered)
	st.meltdown_ended.connect(_on_meltdown_ended)
	_update_hp(st.hp, st.max_hp, 0)
	_update_energy(st.energy, st.max_energy, 0)
	_update_stamina(st.stamina, st.max_stamina, 0)
	_update_heat(st.heat, st.max_heat, 0)


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
