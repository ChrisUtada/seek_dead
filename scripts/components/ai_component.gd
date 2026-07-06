class_name AIComponent
extends Node

enum AIState { IDLE, PATROL, WANDER, ALERT, CHASE, ATTACK, RETURN }

signal state_changed(new_state: int)
signal attack_performed(target: Node2D, damage: float)
signal alerted(target: Node2D)

@export var detect_range: float = 300.0
@export var wander_radius: float = 400.0
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.5
@export var alert_cooldown: float = 2.0
@export var alert_radius: float = 500.0
@export var home_radius: float = 800.0
@export var patrol_points: Array[Vector2] = []

var attack_range: float = 50.0
var current_state: int = AIState.IDLE
var home_position: Vector2

var _nav: NavigationAgent2D
var _target: Node2D = null
var _last_move_dir: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _alert_timer: float = 0.0
var _lost_timer: float = 0.0
var _patrol_index: int = 0
var _nav_bounds: Rect2 = Rect2(10, 10, 1580, 1180)
var _cooldown_alert: bool = false

func _ready():
	_nav = get_parent().get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if not _nav:
		push_error("AIComponent: NavigationAgent2D not found on %s" % get_parent().name)
	else:
		_nav.target_desired_distance = attack_range * 0.8
	home_position = get_parent().global_position
	if patrol_points.size() > 0:
		_change_state(AIState.PATROL)
	else:
		_pick_wander_target()

func set_patrol(points: Array[Vector2]):
	patrol_points = points
	_patrol_index = 0

func set_home(pos: Vector2, radius: float = 800.0):
	home_position = pos
	home_radius = radius

func set_nav_bounds(bounds: Rect2):
	_nav_bounds = bounds

func process_ai(delta):
	if not _nav:
		return
	_attack_timer = max(0, _attack_timer - delta)
	var prev_target = _target
	_target = _find_nearest_player()

	if _target and not prev_target:
		_alert_nearby()

	match current_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.PATROL:
			_process_patrol(delta)
		AIState.WANDER:
			_process_wander(delta)
		AIState.ALERT:
			_process_alert(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)
		AIState.RETURN:
			_process_return(delta)

func _process_idle(delta):
	_last_move_dir = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0:
		if patrol_points.size() > 0:
			_change_state(AIState.PATROL)
		else:
			_change_state(AIState.WANDER)

func _process_patrol(delta):
	if _target and _get_distance_to(_target) < detect_range:
		_change_state(AIState.CHASE)
		return

	var target_pt = patrol_points[_patrol_index]
	var dist = get_parent().global_position.distance_squared_to(target_pt)
	if dist < 30 * 30:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		if _patrol_index == 0:
			_change_state(AIState.IDLE)
			return

	_nav.target_position = patrol_points[_patrol_index]
	if _nav.is_navigation_finished():
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func _process_wander(delta):
	var has_player = _target != null and _get_distance_to(_target) < detect_range
	if has_player:
		_change_state(AIState.CHASE)
		return

	var dist = get_parent().global_position.distance_squared_to(_wander_target)
	if dist < 20 * 20:
		_change_state(AIState.IDLE)
		return

	if _is_out_of_bounds(get_parent().global_position):
		_change_state(AIState.RETURN)
		return

	_nav.target_position = _wander_target
	if _nav.is_navigation_finished():
		_change_state(AIState.IDLE)
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func _process_alert(delta):
	_last_move_dir = Vector2.ZERO
	_alert_timer -= delta
	if _target and _get_distance_to(_target) < detect_range * 1.2:
		_change_state(AIState.CHASE)
		return
	if _alert_timer <= 0:
		if _target and _get_distance_to(_target) < detect_range * 2.0:
			_change_state(AIState.CHASE)
		else:
			_change_state(AIState.WANDER)

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
			_change_state(AIState.ALERT)
			return
	else:
		_lost_timer = 0.0

	if _is_out_of_bounds(get_parent().global_position):
		_change_state(AIState.RETURN)
		return

	var spread = attack_range * 0.6
	var angle = fmod(float(get_parent().get_instance_id()) * 0.001, TAU)
	var offset = Vector2(cos(angle), sin(angle)) * spread
	_nav.target_position = _target.global_position + offset
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

func _process_return(delta):
	var dist = get_parent().global_position.distance_squared_to(home_position)
	if dist < 50 * 50:
		if patrol_points.size() > 0:
			_change_state(AIState.PATROL)
		else:
			_change_state(AIState.WANDER)
		return

	if _target and _get_distance_to(_target) < detect_range:
		_change_state(AIState.CHASE)
		return

	_nav.target_position = home_position
	if _nav.is_navigation_finished():
		_last_move_dir = Vector2.ZERO
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

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
		AIState.PATROL:
			_last_move_dir = Vector2.ZERO
		AIState.ALERT:
			_alert_timer = alert_cooldown
		AIState.ATTACK:
			_attack_timer = 0.0
		AIState.RETURN:
			_last_move_dir = Vector2.ZERO

func _alert_nearby():
	if _cooldown_alert:
		return
	_cooldown_alert = true
	get_tree().create_timer(5.0).timeout.connect(func(): _cooldown_alert = false)
	alerted.emit(_target)
	var allies = get_tree().get_nodes_in_group("enemies")
	var pos = get_parent().global_position
	for ally in allies:
		if ally == get_parent():
			continue
		var ai = ally.get_node_or_null("AIComponent")
		if ai and ai.current_state in [AIState.IDLE, AIState.WANDER, AIState.PATROL]:
			if pos.distance_squared_to(ally.global_position) < alert_radius * alert_radius:
				ai._on_alerted(_target)

func _on_alerted(target: Node2D):
	if current_state in [AIState.IDLE, AIState.WANDER, AIState.PATROL]:
		_target = target
		_change_state(AIState.ALERT)

func _pick_wander_target():
	var parent_pos = get_parent().global_position
	for _attempt in range(10):
		var rand_x = parent_pos.x + randf_range(-wander_radius, wander_radius)
		var rand_y = parent_pos.y + randf_range(-wander_radius, wander_radius)
		rand_x = clamp(rand_x, _nav_bounds.position.x + 20, _nav_bounds.end.x - 20)
		rand_y = clamp(rand_y, _nav_bounds.position.y + 20, _nav_bounds.end.y - 20)
		var target = Vector2(rand_x, rand_y)
		if _target and target.distance_squared_to(get_parent().global_position) > 50 * 50:
			if target.distance_squared_to(home_position) < home_radius * home_radius:
				_wander_target = target
				return
	_wander_target = Vector2(
		randf_range(max(home_position.x - home_radius, _nav_bounds.position.x + 20),
					min(home_position.x + home_radius, _nav_bounds.end.x - 20)),
		randf_range(max(home_position.y - home_radius, _nav_bounds.position.y + 20),
					min(home_position.y + home_radius, _nav_bounds.end.y - 20))
	)

func _is_out_of_bounds(pos: Vector2) -> bool:
	return pos.distance_squared_to(home_position) > home_radius * home_radius

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
	return EntityRegistry.get_nearest_player(get_parent().global_position)

func has_line_of_sight_to(target: Node2D, max_distance: float) -> bool:
	var parent = get_parent() as Node2D
	if not parent:
		return true
	var ray = parent.get_node_or_null("LOSRay") as RayCast2D
	if not ray:
		return true
	var offset = target.global_position - parent.global_position
	if offset.length() > max_distance:
		return false
	ray.global_position = parent.global_position
	ray.target_position = offset
	ray.force_raycast_update()
	return not ray.is_colliding()
