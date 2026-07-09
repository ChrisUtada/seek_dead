extends Node

var players: Array[Node2D] = []
var enemies: Array[Node2D] = []

func _ready():
	process_mode = PROCESS_MODE_ALWAYS

func register_player(node: Node2D):
	if node in players:
		return
	players.append(node)
	node.tree_exited.connect(_on_player_exited.bind(node))

func register_enemy(node: Node2D):
	if node in enemies:
		return
	enemies.append(node)
	node.tree_exited.connect(_on_enemy_exited.bind(node))

func unregister_player(node: Node2D):
	players.erase(node)

func unregister_enemy(node: Node2D):
	enemies.erase(node)

func _on_player_exited(node: Node2D):
	players.erase(node)

func _on_enemy_exited(node: Node2D):
	enemies.erase(node)

func get_nearest_player(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for p in players:
		if not is_instance_valid(p):
			continue
		var d = from.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best

func get_enemies_in_range(from: Vector2, radius: float) -> Array[Node2D]:
	var r2 = radius * radius
	var result: Array[Node2D] = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if from.distance_squared_to(e.global_position) <= r2:
			result.append(e)
	return result

func get_player_count() -> int:
	return players.size()

func get_enemy_count() -> int:
	return enemies.size()

func clear_all():
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	players.clear()
