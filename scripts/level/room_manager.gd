extends Node

const _DoorScript = preload("res://scripts/level/door_marker.gd")

var _player: Node2D
var _current_room: Node2D
var _room_scenes: Array[PackedScene]
var _transition: ColorRect
var _root: Node
var _transitioning: bool = false

var _room_cache: Dictionary = {}
var _current_pos: Vector2i = Vector2i.ZERO


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var paths = [
		"res://scenes/rooms/room_1.tscn",
		"res://scenes/rooms/room_2.tscn",
	]
	for p in paths:
		var s = load(p)
		if s:
			_room_scenes.append(s)

	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_transition = ColorRect.new()
	_transition.size = Vector2(800, 600)
	_transition.color = Color(0, 0, 0, 0)
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_transition)


func enter_first_room(player: Node2D, root: Node):
	if _room_scenes.is_empty():
		return
	_player = player
	_root = root
	_current_pos = Vector2i.ZERO
	_load_room(-1)


func _load_room(entrance_direction: int):
	print("RoomMgr _load_room dir=", entrance_direction, " transitioning=", _transitioning)
	if _transitioning:
		print("RoomMgr skip: already transitioning")
		return
	_transitioning = true

	_transition.mouse_filter = Control.MOUSE_FILTER_STOP
	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 1), 0.3)
	t.tween_callback(_do_switch.bind(entrance_direction))
	t.tween_property(_transition, "color", Color(0, 0, 0, 0), 0.3)
	t.finished.connect(_end_transition)
	# safety timeout
	get_tree().create_timer(8.0, false).timeout.connect(_end_transition)


func _end_transition():
	if not _transitioning:
		return
	_transitioning = false
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("RoomMgr _end_transition")


func _do_switch(entrance_direction: int):
	print("RoomMgr _do_switch dir=", entrance_direction, " old_pos=", _current_pos)
	_current_pos = _next_pos(entrance_direction)
	print("RoomMgr _do_switch new_pos=", _current_pos)

	if not _player:
		push_error("RoomMgr: _player is null")
		return
	if not _root:
		push_error("RoomMgr: _root is null")
		return

	if is_instance_valid(_current_room):
		var p = _current_room.get_parent()
		if p:
			p.remove_child(_current_room)

	if _room_cache.has(_current_pos):
		_current_room = _room_cache[_current_pos]
		_root.add_child(_current_room)
		_root.move_child(_current_room, 0)
		print("RoomMgr reused cached room at ", _current_pos)
	else:
		var scene = _room_scenes[randi() % _room_scenes.size()]
		var room = scene.instantiate()
		_room_cache[_current_pos] = room
		_current_room = room
		_root.add_child(room)
		_root.move_child(room, 0)
		print("RoomMgr instantiated new room at ", _current_pos, " scene=", scene.resource_path)

	var spawn = _current_room.get_node_or_null("PlayerSpawn")
	if spawn:
		_player.global_position = spawn.global_position
		print("RoomMgr placed player at PlayerSpawn ", spawn.global_position)
	else:
		var tml = _current_room.find_child("TileMapLayer")
		if tml:
			var r = tml.get_used_rect() as Rect2i
			_player.global_position = Vector2(r.get_center()) * _tile_size(tml)
			print("RoomMgr placed player at TileMap center ", _player.global_position)
		else:
			_player.global_position = Vector2(400, 300)
			print("RoomMgr placed player at fallback 400,300")

	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			if not child.player_entered.is_connected(_on_door_entered):
				child.player_entered.connect(_on_door_entered)
				print("RoomMgr connected door signal on ", child.name)


func _on_door_entered(door_direction: int):
	print("RoomMgr _on_door_entered dir=", door_direction)
	_load_room(door_direction)


func _next_pos(door_dir: int) -> Vector2i:
	match door_dir:
		DoorMarker.Direction.UP: return _current_pos + Vector2i(0, -1)
		DoorMarker.Direction.DOWN: return _current_pos + Vector2i(0, 1)
		DoorMarker.Direction.LEFT: return _current_pos + Vector2i(-1, 0)
		DoorMarker.Direction.RIGHT: return _current_pos + Vector2i(1, 0)
	return _current_pos


func _opposite(d: int) -> int:
	match d:
		DoorMarker.Direction.UP: return DoorMarker.Direction.DOWN
		DoorMarker.Direction.DOWN: return DoorMarker.Direction.UP
		DoorMarker.Direction.LEFT: return DoorMarker.Direction.RIGHT
		DoorMarker.Direction.RIGHT: return DoorMarker.Direction.LEFT
	return d

func _tile_size(tml: TileMapLayer) -> int:
	if tml and tml.tile_set:
		return tml.tile_set.tile_size.x
	return 16
