class_name RoomGenerator
extends RefCounted

const GAP_TILES := 3
const _DoorScript = preload("res://scripts/level/door_marker.gd")

class PlacedRoom:
	var node: Node2D
	var tilemap: TileMapLayer
	var doors = []
	var door_connected = []
	var world_rect: Rect2


func generate(room_paths: Array[String], max_rooms: int = 4, rng_seed: int = -1) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed

	var root = Node2D.new()
	root.name = "GeneratedLevel"
	var placed: Array[PlacedRoom] = []

	var scenes: Array[PackedScene] = []
	for path in room_paths:
		var s = load(path)
		if s:
			scenes.append(s)
	if scenes.is_empty():
		return {}

	var first = _place_room(scenes[rng.randi_range(0, scenes.size() - 1)], Vector2.ZERO)
	if first == null:
		return {}
	root.add_child(first.node)
	placed.append(first)

	var attempts = 0
	while placed.size() < max_rooms and attempts < max_rooms * 15:
		attempts += 1
		var candidates: Array[Array] = []
		for pr in placed:
			for i in pr.doors.size():
				if not pr.door_connected[i]:
					candidates.append([pr, i])
		if candidates.is_empty():
			break

		var pick = candidates[rng.randi_range(0, candidates.size() - 1)]
		var src_room: PlacedRoom = pick[0]
		var src_idx: int = pick[1]
		var src_door = src_room.doors[src_idx]
		var src_dir = src_door.direction

		var new_scene = scenes[rng.randi_range(0, scenes.size() - 1)]
		var new_room = _instantiate_room(new_scene)
		if new_room == null:
			continue

		var compat: Array[int] = []
		for i in new_room.doors.size():
			if _is_opposite(src_dir, new_room.doors[i].direction):
				compat.append(i)
		if compat.is_empty():
			new_room.node.queue_free()
			continue

		var dst_idx = compat[rng.randi_range(0, compat.size() - 1)]
		var dst_door = new_room.doors[dst_idx]

		var pos = _calc_pos(src_room, src_door, new_room, dst_door)
		new_room.node.position = pos
		_refresh_rect(new_room)

		if _has_overlap(new_room, placed):
			new_room.node.queue_free()
			continue

		root.add_child(new_room.node)
		_create_corridor(root, src_room, src_door, new_room, dst_door)
		src_room.door_connected[src_idx] = true
		new_room.door_connected[dst_idx] = true
		placed.append(new_room)

	var spawn = Vector2.ZERO
	var marker = first.node.get_node_or_null("PlayerSpawn")
	if marker:
		spawn = marker.global_position
	else:
		var r = first.world_rect
		spawn = r.get_center()

	return { "root": root, "player_spawn": spawn }


func _place_room(scene: PackedScene, pos: Vector2) -> PlacedRoom:
	var result = _instantiate_room(scene)
	if result == null:
		return null
	result.node.position = pos
	_refresh_rect(result)
	return result


func _instantiate_room(scene: PackedScene) -> PlacedRoom:
	var node = scene.instantiate()
	if not node is Node2D:
		return null

	var result = PlacedRoom.new()
	result.node = node

	var tilemap = _find_tilemap(node)
	result.tilemap = tilemap

	result.doors = []
	result.door_connected = []
	for child in node.find_children("*", "Marker2D"):
		if child.get_script() == _DoorScript:
			result.doors.append(child)
			result.door_connected.append(false)

	return result


func _refresh_rect(pr: PlacedRoom):
	if pr.tilemap:
		var used = pr.tilemap.get_used_rect()
		if used.size != Vector2i.ZERO:
			var ts = pr.tilemap.tile_set.tile_size if pr.tilemap.tile_set else Vector2i(16, 16)
			var tl = pr.node.position + Vector2(used.position) * Vector2(ts)
			var br = pr.node.position + Vector2(used.end) * Vector2(ts)
			pr.world_rect = Rect2(tl, br - tl)
			return
	pr.world_rect = Rect2(pr.node.position, Vector2(32, 32))


func _calc_pos(src_room: PlacedRoom, src_door: Marker2D, new_room: PlacedRoom, dst_door: Marker2D) -> Vector2:
	var src_door_world = src_room.node.position + src_door.position
	var dir_vec = _dir_vec(src_door.direction)
	var offset = dir_vec * GAP_TILES * _tile_size(src_room)
	return src_door_world - dst_door.position + offset


func _tile_size(pr: PlacedRoom) -> int:
	if pr.tilemap and pr.tilemap.tile_set:
		return pr.tilemap.tile_set.tile_size.x
	return 16


func _has_overlap(pr: PlacedRoom, others: Array[PlacedRoom]) -> bool:
	var margin = 4
	var r = pr.world_rect.grow(margin)
	for other in others:
		if r.intersects(other.world_rect, true):
			return true
	return false


func _is_opposite(a: int, b: int) -> bool:
	return (a == 0 and b == 1) or (a == 1 and b == 0) or (a == 2 and b == 3) or (a == 3 and b == 2)


func _dir_vec(d: int) -> Vector2:
	match d:
		0: return Vector2.UP
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		3: return Vector2.RIGHT
	return Vector2.ZERO


func _find_tilemap(node: Node) -> TileMapLayer:
	for child in node.find_children("*", "TileMapLayer"):
		return child
	return null


func _create_corridor(root: Node2D, src_room: PlacedRoom, src_door: Marker2D, dst_room: PlacedRoom, dst_door: Marker2D):
	var ts = _tile_size(src_room)
	var src_world = src_room.node.position + src_door.position
	var dst_world = dst_room.node.position + dst_door.position
	var dir = _dir_vec(src_door.direction)

	var start_tile = Vector2i(
		int(floor((src_world.x + dir.x * ts) / ts)),
		int(floor((src_world.y + dir.y * ts) / ts))
	)
	var end_tile = Vector2i(
		int(floor((dst_world.x - dir.x * ts) / ts)),
		int(floor((dst_world.y - dir.y * ts) / ts))
	)

	var min_p = Vector2i(min(start_tile.x, end_tile.x), min(start_tile.y, end_tile.y))
	var max_p = Vector2i(max(start_tile.x, end_tile.x), max(start_tile.y, end_tile.y))

	var ts_set = src_room.tilemap.tile_set
	if ts_set == null:
		return
	var corridor = TileMapLayer.new()
	corridor.name = "Corridor"
	corridor.tile_set = ts_set
	root.add_child(corridor)
	root.move_child(corridor, 0)

	var src_id = 0
	var ids = ts_set.get_source_list()
	if ids.size() > 0:
		src_id = ids[0]

	for x in range(min_p.x, max_p.x + 1):
		for y in range(min_p.y, max_p.y + 1):
			corridor.set_cell(Vector2i(x, y), src_id, Vector2i(0, 0))


func _bake_navigation(root: Node2D):
	pass
