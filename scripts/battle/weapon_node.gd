class_name WeaponNode
extends Node2D

const _WeaponBase = preload("res://scripts/battle/weapon_base.gd")

signal hit_landed(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D)
signal attack_finished(weapon_node: WeaponNode, hit_count: int)

enum WeaponState { IDLE, ACTIVE, COOLDOWN }

@export var stats: WeaponBase

var shooter: Node2D = null
var aim_direction: Vector2 = Vector2.RIGHT
var weapon_color: Color = Color.WHITE
var is_attacking: bool = false
var attack_speed_modifier: float = 1.0

var _ws: WeaponState = WeaponState.IDLE
var _active_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _flash_timer: float = 0.0
var _swing_progress: float = 0.0
var _is_swinging: bool = false
var _trail_angles: Array[float] = []
var _trail_alphas: Array[float] = []
var _trail_lifetime: float = 0.15


func _process(delta):
	match _ws:
		WeaponState.ACTIVE:
			_active_timer -= delta
			if _active_timer <= 0:
				_end_active()
		WeaponState.COOLDOWN:
			_cooldown_timer -= delta
			if _cooldown_timer <= 0:
				_ws = WeaponState.IDLE
	_update_visual(delta)


func can_attack() -> bool:
	return _ws == WeaponState.IDLE and stats != null


func get_cooldown_time() -> float:
	return 1.0 / (stats.attack_speed * attack_speed_modifier) if stats else 1.0


func _start_attack():
	_ws = WeaponState.ACTIVE
	is_attacking = true
	_active_timer = 0.15
	_cooldown_timer = get_cooldown_time()


func _end_active():
	_ws = WeaponState.COOLDOWN
	is_attacking = false
	attack_finished.emit(self, 0)


func attack():
	pass


func flash_range():
	_flash_timer = 0.15
	queue_redraw()


func swing():
	_is_swinging = true
	_swing_progress = 0.0


func on_equip():
	visible = true


func on_unequip():
	visible = false


func _update_visual(delta):
	if not stats:
		return
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0:
			queue_redraw()
	if _is_swinging:
		_swing_progress += delta * 8.0
		var angle = _swing_progress * PI * 0.8 - PI * 0.4
		if _trail_angles.size() < 32:
			_trail_angles.append(angle)
			_trail_alphas.append(1.0)
		queue_redraw()
		if _swing_progress >= 1.0:
			_is_swinging = false
			_swing_progress = 0.0
			queue_redraw()
	for i in range(_trail_alphas.size() - 1, -1, -1):
		_trail_alphas[i] -= delta / _trail_lifetime
		if _trail_alphas[i] <= 0:
			_trail_angles.remove_at(i)
			_trail_alphas.remove_at(i)


func _draw():
	if not stats:
		return
	if _flash_timer > 0:
		var alpha = _flash_timer / 0.15
		draw_arc(Vector2.ZERO, stats.attack_range, 0, TAU, 32, Color(weapon_color.r, weapon_color.g, weapon_color.b, alpha * 0.4), 2.0, true)
	for i in range(_trail_angles.size()):
		var a = _trail_alphas[i]
		if a <= 0:
			continue
		var angle = _trail_angles[i]
		draw_arc(Vector2.ZERO, stats.attack_range * 0.5, -PI * 0.4, angle, 12, Color(weapon_color.r, weapon_color.g, weapon_color.b, a * 0.3), 3.0, true)
	if _is_swinging:
		var angle = _swing_progress * PI * 0.8 - PI * 0.4
		draw_arc(Vector2.ZERO, stats.attack_range * 0.5, -PI * 0.4, angle, 16, Color(weapon_color.r, weapon_color.g, weapon_color.b, 0.6), 4.0, true)
	if stats.attack_range > 100:
		var tip = Vector2(stats.attack_range * 0.7, 0)
		draw_circle(tip, 4, Color(weapon_color.r, weapon_color.g, weapon_color.b, 0.3))
