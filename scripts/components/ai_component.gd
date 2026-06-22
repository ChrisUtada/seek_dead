class_name AIComponent
extends Node

enum AIState { IDLE, WANDER, CHASE, ATTACK }

signal state_changed(new_state: int)
signal attack_performed(target: Node2D, damage: float)

@export var detect_range: float = 300.0
@export var wander_radius: float = 400.0
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.5

var attack_range: float = 50.0
var current_state: int = AIState.IDLE

var _nav: NavigationAgent2D
var _target: Node2D = null
var _last_move_dir: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _lost_timer: float = 0.0
var _nav_bounds: Rect2 = Rect2(10, 10, 1580, 1180)

func _ready():
	_nav = get_parent().get_node("NavigationAgent2D")
	_pick_wander_target()

func process_ai(delta):
	_attack_timer = max(0, _attack_timer - delta)
	_target = _find_nearest_player()

	match current_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.WANDER:
			_process_wander(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)

func _process_idle(delta):
	_last_move_dir = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0:
		_change_state(AIState.WANDER)

func _process_wander(delta):
	var has_player = _target != null and _get_distance_to(_target) < detect_range
	if has_player:
		_change_state(AIState.CHASE)
		return

	var dist = get_parent().global_position.distance_squared_to(_wander_target)
	if dist < 20 * 20:
		_change_state(AIState.IDLE)
		return

	_nav.target_position = _wander_target
	if _nav.is_navigation_finished():
		_change_state(AIState.IDLE)
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func _process_chase(delta):
	if not _target:
		_change_state(AIState.WANDER)
		return

	var dist = _get_distance_to(_target)
	if dist < attack_range:
		_change_state(AIState.ATTACK)
		return

	if dist >= detect_range:
		_lost_timer += delta
		if _lost_timer > 3.0:
			_change_state(AIState.WANDER)
			return
	else:
		_lost_timer = 0.0

	_nav.target_position = _target.global_position
	if _nav.is_navigation_finished():
		_last_move_dir = Vector2.ZERO
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func _process_attack(delta):
	_last_move_dir = Vector2.ZERO

	if not _target:
		_change_state(AIState.WANDER)
		return

	if _get_distance_to(_target) >= attack_range * 1.2:
		_change_state(AIState.CHASE)
		return

	if _attack_timer <= 0:
		_attack_timer = attack_cooldown
		attack_performed.emit(_target, attack_damage)

func _change_state(new_state: int):
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)

	match new_state:
		AIState.IDLE:
			_idle_timer = randf_range(1.0, 3.0)
		AIState.WANDER:
			_pick_wander_target()
		AIState.ATTACK:
			_attack_timer = 0.0

func _pick_wander_target():
	var parent_pos = get_parent().global_position
	for _attempt in range(10):
		var rand_x = parent_pos.x + randf_range(-wander_radius, wander_radius)
		var rand_y = parent_pos.y + randf_range(-wander_radius, wander_radius)
		rand_x = clamp(rand_x, _nav_bounds.position.x + 20, _nav_bounds.end.x - 20)
		rand_y = clamp(rand_y, _nav_bounds.position.y + 20, _nav_bounds.end.y - 20)
		var target = Vector2(rand_x, rand_y)
		if _target and target.distance_squared_to(get_parent().global_position) > 50 * 50:
			_wander_target = target
			return
	_wander_target = Vector2(
		randf_range(_nav_bounds.position.x + 20, _nav_bounds.end.x - 20),
		randf_range(_nav_bounds.position.y + 20, _nav_bounds.end.y - 20)
	)

func get_move_direction() -> Vector2:
	return _last_move_dir

func get_target() -> Node2D:
	return _target

func is_player_in_attack_range() -> bool:
	if not _target:
		return false
	return _get_distance_to(_target) < attack_range

func _get_distance_to(target: Node2D) -> float:
	return sqrt(get_parent().global_position.distance_squared_to(target.global_position))

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return null
	return players[0]
