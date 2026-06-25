extends Node

const _DoorScript = preload("res://scripts/level/door_marker.gd")

var _player: Node2D
var _current_room: Node2D
var _room_configs: Array[RoomConfig]
var _transition: ColorRect
var _root: Node
var _transitioning: bool = false

var _room_cache: Dictionary = {}
var _current_pos: Vector2i = Vector2i.ZERO
var _last_config_index: int = -1


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_configs()

	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_transition = ColorRect.new()
	_transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition.color = Color(0, 0, 0, 0)
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_transition)


func _load_configs():
	var dir = DirAccess.open("res://resources/rooms")
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file:
			if file.ends_with(".tres"):
				var cfg = load("res://resources/rooms/" + file) as RoomConfig
				if cfg and cfg.scene:
					_room_configs.append(cfg)
			file = dir.get_next()

	if _room_configs.is_empty():
		var fallback = [
			"res://resources/rooms/room_1.tres",
			"res://resources/rooms/room_2.tres",
		]
		for p in fallback:
			var cfg = load(p) as RoomConfig
			if cfg and cfg.scene:
				_room_configs.append(cfg)


func enter_first_room(player: Node2D, root: Node):
	if _room_configs.is_empty():
		push_error("RoomMgr: 无房间配置")
		return
	_player = player
	_root = root
	_current_pos = Vector2i.ZERO
	_do_switch(-1)


func _load_room(entrance_direction: int):
	if _transitioning:
		return
	_transitioning = true

	_transition.mouse_filter = Control.MOUSE_FILTER_STOP
	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 1), 0.3)
	t.tween_callback(_do_switch.bind(entrance_direction))
	t.tween_property(_transition, "color", Color(0, 0, 0, 0), 0.3)
	t.finished.connect(_end_transition)
	get_tree().create_timer(8.0, false).timeout.connect(_end_transition)


func _end_transition():
	if not _transitioning:
		return
	_transitioning = false
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _do_switch(entrance_direction: int):
	_current_pos = _next_pos(entrance_direction)

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
	else:
		var config = _pick_config()
		_last_config_index = _room_configs.find(config)
		var room = config.scene.instantiate()
		_room_cache[_current_pos] = room
		_current_room = room
		_root.add_child(room)
		_root.move_child(room, 0)
		_spawn_enemies(config, room)

	_position_player()

	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			if not child.player_entered.is_connected(_on_door_entered):
				child.player_entered.connect(_on_door_entered)


func _spawn_enemies(config: RoomConfig, room: Node2D):
	var markers: Array[Marker2D] = []
	for n in room.find_children("SpawnMarker*", "Marker2D", true, false):
		if n is Marker2D:
			markers.append(n)
	if markers.is_empty():
		push_warning("RoomMgr: 房间 %s 没有 SpawnMarker" % config.room_name)
		return
	var count = randi_range(config.min_enemies, min(config.max_enemies, markers.size()))
	markers.shuffle()
	for i in range(count):
		var marker = markers[i]
		var enemy_scene = config.enemy_pool.pick_random()
		if not enemy_scene:
			continue
		var enemy = enemy_scene.instantiate()
		enemy.global_position = marker.global_position
		room.add_child(enemy)


func _position_player():
	var spawn = _current_room.get_node_or_null("PlayerSpawn")
	if spawn:
		_player.global_position = spawn.global_position
		return
	var tml = _current_room.find_child("TileMapLayer") as TileMapLayer
	if tml:
		var r = tml.get_used_rect() as Rect2i
		_player.global_position = Vector2(r.get_center()) * _tile_size(tml)
	else:
		_player.global_position = Vector2(320, 180)


func _pick_config() -> RoomConfig:
	var n = _room_configs.size()
	if n <= 0:
		return null
	if n <= 1:
		return _room_configs[0]
	var idx = randi() % n
	if idx == _last_config_index:
		idx = (idx + 1) % n
	return _room_configs[idx]


func _on_door_entered(door_direction: int):
	_load_room(door_direction)


func _next_pos(door_dir: int) -> Vector2i:
	match door_dir:
		DoorMarker.Direction.UP: return _current_pos + Vector2i(0, -1)
		DoorMarker.Direction.DOWN: return _current_pos + Vector2i(0, 1)
		DoorMarker.Direction.LEFT: return _current_pos + Vector2i(-1, 0)
		DoorMarker.Direction.RIGHT: return _current_pos + Vector2i(1, 0)
	return _current_pos


func _tile_size(tml: TileMapLayer) -> int:
	if tml and tml.tile_set:
		return tml.tile_set.tile_size.x
	return 16
