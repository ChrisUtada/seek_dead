extends Node2D

var _hp_ratio: float = 1.0
var _bar_width: float = 40.0
var _bar_height: float = 4.0
var _effect_dots: Array[int] = []

var _effect_colors = {
	0: Color(0.5, 0.0, 0.5),
	1: Color(1.0, 0.5, 0.0),
	2: Color(0.5, 0.8, 1.0),
	3: Color(1.0, 1.0, 0.0),
	4: Color(0.5, 0.5, 0.5),
	5: Color(0.8, 0.2, 0.2),
	6: Color(0.2, 0.8, 0.2),
}

func _ready():
	var p = get_parent()
	if p.has_method("get_hp_ratio"):
		_hp_ratio = p.get_hp_ratio()
	if p.state:
		p.state.hp_changed.connect(_on_hp_changed)
	if p.effects:
		p.effects.effect_applied.connect(_on_effect_applied)
		p.effects.effect_expired.connect(_on_effect_expired)

func _on_hp_changed(current: float, max_val: float, _delta: float):
	_hp_ratio = current / max_val if max_val > 0 else 0.0
	queue_redraw()

func _on_effect_applied(et: int, _name: String):
	if et not in _effect_dots:
		_effect_dots.append(et)
		queue_redraw()

func _on_effect_expired(et: int, _name: String):
	_effect_dots.erase(et)
	queue_redraw()

func _draw():
	var offset = Vector2(-_bar_width / 2, -28)
	draw_rect(Rect2(offset, Vector2(_bar_width, _bar_height)), Color(0.15, 0.15, 0.15, 0.9))
	var fill_w = _bar_width * clamp(_hp_ratio, 0.0, 1.0)
	var bar_color = Color(0.8, 0.15, 0.15) if _hp_ratio > 0.3 else Color(1.0, 0.6, 0.0)
	draw_rect(Rect2(offset, Vector2(fill_w, _bar_height)), bar_color)

	var dot_y = offset.y - 5
	for i in _effect_dots.size():
		var c = _effect_colors.get(_effect_dots[i], Color(1, 1, 1))
		var cx = offset.x + i * 10 + 5
		draw_circle(Vector2(cx, dot_y), 3.0, c)
