class_name BossAIComponent
extends Node

enum BossState { IDLE, CHASE, MELEE_SLAM, CHARGE, RANGED_BURST }

signal state_changed(new_state: int)
signal perform_melee_slam(target: Node2D)
signal perform_charge(target: Node2D)
signal perform_ranged_burst(target: Node2D)

@export var detect_range: float = 600.0
@export var melee_range: float = 70.0
@export var charge_range: float = 250.0
@export var phase2_hp_ratio: float = 0.6
@export var phase3_hp_ratio: float = 0.3

var phase: int = 1
var current_state: int = BossState.IDLE

var _nav: NavigationAgent2D
var _target: Node2D = null
var _last_move_dir: Vector2 = Vector2.ZERO
var _decision_timer: float = 0.0
var _lost_timer: float = 0.0
var _idle_timer: float = 0.0
var _nav_bounds: Rect2 = Rect2(10, 10, 1580, 1180)

func _ready():
	_nav = get_parent().get_node("NavigationAgent2D")

func check_phase(hp_ratio: float):
	var new_phase = 3 if hp_ratio < phase3_hp_ratio else (2 if hp_ratio < phase2_hp_ratio else 1)
	if new_phase != phase:
		phase = new_phase

func process_ai(delta):
	_decision_timer = max(0, _decision_timer - delta)
	_target = _find_nearest_player()

	match current_state:
		BossState.IDLE:
			_process_idle()
		BossState.CHASE:
			_process_chase(delta)
		BossState.MELEE_SLAM:
			_process_melee_slam(delta)
		BossState.CHARGE:
			_process_charge(delta)
		BossState.RANGED_BURST:
			_process_ranged_burst(delta)

func _process_idle():
	_last_move_dir = Vector2.ZERO
	_idle_timer -= get_process_delta_time()
	if _idle_timer <= 0:
		_change_state(BossState.CHASE)

func _process_chase(delta):
	if not _target:
		_change_state(BossState.IDLE)
		return

	var dist = _get_distance_to(_target)

	if dist < melee_range:
		_change_state(BossState.MELEE_SLAM)
		return

	if dist >= detect_range:
		_lost_timer += delta
		if _lost_timer > 4.0:
			_change_state(BossState.IDLE)
			return
	else:
		_lost_timer = 0.0

	if _decision_timer <= 0:
		var should_charge = dist > charge_range * 0.5 and dist < charge_range * 1.5 and phase >= 1
		var should_ranged = dist > melee_range * 2 and phase >= 2 and randf() < 0.3
		if should_ranged:
			_change_state(BossState.RANGED_BURST)
			return
		if should_charge and randf() < 0.35:
			_change_state(BossState.CHARGE)
			return
		_decision_timer = 1.5

	_nav.target_position = _target.global_position
	if _nav.is_navigation_finished():
		_last_move_dir = Vector2.ZERO
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func _process_melee_slam(delta):
	_last_move_dir = Vector2.ZERO
	if _decision_timer <= 0:
		perform_melee_slam.emit(_target)
		if _get_distance_to(_target) < melee_range:
			_decision_timer = _get_attack_cooldown()
		else:
			_change_state(BossState.CHASE)

func _process_charge(delta):
	if not _target:
		_change_state(BossState.CHASE)
		return

	_last_move_dir = Vector2.ZERO

	if _decision_timer <= 0:
		perform_charge.emit(_target)
		_decision_timer = _get_attack_cooldown()
		_change_state(BossState.CHASE)

func _process_ranged_burst(delta):
	_last_move_dir = Vector2.ZERO
	if not _target:
		_change_state(BossState.CHASE)
		return
	if _decision_timer <= 0:
		perform_ranged_burst.emit(_target)
		_decision_timer = _get_attack_cooldown()
		_change_state(BossState.CHASE)

func _change_state(new_state: int):
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)

	match new_state:
		BossState.IDLE:
			_idle_timer = randf_range(0.5, 1.5)
		BossState.CHASE:
			_decision_timer = randf_range(0.5, 1.5)
		BossState.MELEE_SLAM:
			_decision_timer = 0.3
		BossState.CHARGE:
			_decision_timer = 0.2
		BossState.RANGED_BURST:
			_decision_timer = 0.4

func _get_attack_cooldown() -> float:
	match phase:
		3: return 0.6
		2: return 0.9
		_: return 1.2

func get_move_direction() -> Vector2:
	return _last_move_dir

func get_target() -> Node2D:
	return _target

func _get_distance_to(target: Node2D) -> float:
	return sqrt(get_parent().global_position.distance_squared_to(target.global_position))

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return null
	return players[0]
