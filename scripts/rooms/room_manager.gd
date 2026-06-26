extends Node

const _DoorScript = preload("res://scripts/rooms/door_marker.gd")

var _player: Node2D
var _current_room: Node2D
var _room_configs: Array[RoomConfig]
var _transition: ColorRect
var _root: Node
var _transitioning: bool = false
var _last_config_index: int = -1
var _doors_unlocked: bool = false


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


func _reset_state():
	if is_instance_valid(_current_room):
		var p = _current_room.get_parent()
		if p:
			p.remove_child(_current_room)
	_current_room = null
	_transitioning = false


func enter_first_room(player: Node2D, root: Node):
	_reset_state()
	if _room_configs.is_empty():
		push_error("RoomMgr: 无房间配置")
		return
	_player = player
	_root = root
	_do_switch()


func _load_room(entrance_direction: int):
	if _transitioning:
		return
	_transitioning = true

	_transition.mouse_filter = Control.MOUSE_FILTER_STOP
	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 1), 0.3)
	t.tween_callback(_do_switch)
	t.tween_property(_transition, "color", Color(0, 0, 0, 0), 0.3)
	t.finished.connect(_end_transition)
	get_tree().create_timer(8.0, false).timeout.connect(_end_transition)


func _end_transition():
	if not _transitioning:
		return
	_transitioning = false
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _do_switch():
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
		_current_room = null

	var config = _pick_config()
	var room = config.scene.instantiate()
	_current_room = room
	_root.add_child(room)
	_root.move_child(room, 0)
	_spawn_enemies(config, room)
	_doors_unlocked = false
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
	if not markers.is_empty():
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

	if config.boss_count > 0 and not config.boss_pool.is_empty():
		var boss_marker = room.get_node_or_null("SpawnMarker_Boss")
		for _j in range(min(config.boss_count, config.boss_pool.size())):
			var boss_scene = config.boss_pool.pick_random()
			if not boss_scene:
				continue
			var boss = boss_scene.instantiate()
			if boss_marker:
				boss.global_position = boss_marker.global_position
			else:
				var pspawn = room.get_node_or_null("PlayerSpawn")
				boss.global_position = (pspawn.global_position + Vector2(0, -80)) if pspawn else Vector2(320, 180)
			room.add_child(boss)


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
	_last_config_index = idx
	return _room_configs[idx]


func _process(_delta):
	if _doors_unlocked:
		return
	if not is_instance_valid(_current_room):
		return
	if EntityRegistry.get_enemy_count() <= 0:
		_unlock_doors()

func _unlock_doors():
	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			child.unlock()
	_doors_unlocked = true

func _on_door_entered(door_direction: int):
	_load_room(door_direction)


func _tile_size(tml: TileMapLayer) -> int:
	if tml and tml.tile_set:
		return tml.tile_set.tile_size.x
	return 16
