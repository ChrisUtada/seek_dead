extends Node2D

var _color: Color = Color(1, 1, 1)
var _range: float = 40.0
var _is_melee: bool = true
var _flash_timer: float = 0.0
var _swing_progress: float = 0.0
var _is_swinging: bool = false
var _trail_angles: Array[float] = []
var _trail_alphas: Array[float] = []
var _trail_lifetime: float = 0.15

func set_weapon(color: Color, weapon_range: float, is_melee: bool, texture: Texture2D = null, offset: Vector2 = Vector2.ZERO):
	_color = color
	_range = weapon_range
	_is_melee = is_melee
	var sprite = get_node_or_null("WeaponSprite")
	if sprite:
		sprite.texture = texture
		sprite.offset = offset
	queue_redraw()

func flash_range():
	_flash_timer = 0.15
	queue_redraw()

func swing():
	_is_swinging = true
	_swing_progress = 0.0

func _process(delta):
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			queue_redraw()
	if _is_swinging:
		_swing_progress += delta * 8.0
		var angle = _swing_progress * PI * 0.8 - PI * 0.4
		_trail_angles.append(angle)
		_trail_alphas.append(1.0)
		queue_redraw()
		if _swing_progress >= 1.0:
			_is_swinging = false
			_swing_progress = 0.0
			rotation = 0.0
			queue_redraw()
	for i in range(_trail_alphas.size() - 1, -1, -1):
		_trail_alphas[i] -= delta / _trail_lifetime
		if _trail_alphas[i] <= 0:
			_trail_angles.remove_at(i)
			_trail_alphas.remove_at(i)

func _draw():
	if _is_melee:
		_draw_range_indicator()

	if _flash_timer > 0:
		var alpha = _flash_timer / 0.15
		draw_arc(Vector2.ZERO, _range, 0, TAU, 32, Color(_color.r, _color.g, _color.b, alpha * 0.4), 2.0, true)

	for i in range(_trail_angles.size()):
		var a = _trail_alphas[i]
		if a <= 0:
			continue
		var angle = _trail_angles[i]
		draw_arc(Vector2.ZERO, _range * 0.5, -PI * 0.4, angle, 12, Color(_color.r, _color.g, _color.b, a * 0.3), 3.0, true)

	if _is_swinging:
		var angle = _swing_progress * PI * 0.8 - PI * 0.4
		draw_arc(Vector2.ZERO, _range * 0.5, -PI * 0.4, angle, 16, Color(_color.r, _color.g, _color.b, 0.6), 4.0, true)

func _draw_range_indicator():
	var tip = Vector2(_range * 0.7, 0)
	draw_circle(tip, 4, Color(_color.r, _color.g, _color.b, 0.3))
