class_name AIComponent
extends Node

@export var attack_range: float = 50.0

var _nav: NavigationAgent2D
var _target: Node2D = null
var _last_move_dir: Vector2 = Vector2.ZERO

func _ready():
	_nav = get_parent().get_node("NavigationAgent2D")

func process_ai(_delta):
	_target = _find_nearest_player()
	if not _target:
		_last_move_dir = Vector2.ZERO
		return

	_nav.target_position = _target.global_position

	if _nav.is_navigation_finished():
		_last_move_dir = Vector2.ZERO
	else:
		var next = _nav.get_next_path_position()
		_last_move_dir = get_parent().global_position.direction_to(next)

func get_move_direction() -> Vector2:
	return _last_move_dir

func get_target() -> Node2D:
	return _target

func is_player_in_attack_range() -> bool:
	if not _target:
		return false
	return get_parent().global_position.distance_squared_to(_target.global_position) < attack_range * attack_range

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return null
	return players[0]
