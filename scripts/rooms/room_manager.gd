extends Node

const _DoorScript = preload("res://scripts/rooms/door_marker.gd")
const _WaveConfig = preload("res://scripts/rooms/wave_config.gd")
const _RoomSequence = preload("res://scripts/rooms/room_sequence.gd")

var _player: Node2D
var _current_room: Node2D
var _current_config: RoomConfig
var _room_configs: Array[RoomConfig]
var _transition: ColorRect
var _root: Node
var _transitioning: bool = false
var _doors_unlocked: bool = false

var _room_sequence: Array[int] = []
var _sequence_index: int = 0

var _active_waves: Array[Resource] = []
var _current_wave_index: int = 0
var _spawning_wave: bool = false
var _pending_wave: bool = false
var _pending_timers: Array = []
var _wave_broadcasted: bool = false

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

	EventManager.room_cleared.connect(_on_room_cleared)


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
	_clear_pending_timers()
	_active_waves.clear()
	_current_wave_index = 0
	_spawning_wave = false
	_pending_wave = false
	_wave_broadcasted = false
	_current_config = null
	if is_instance_valid(_current_room):
		var p = _current_room.get_parent()
		if p:
			p.remove_child(_current_room)
	_current_room = null


func _clear_pending_timers():
	_pending_wave = false
	_pending_timers.clear()


func enter_first_room(player: Node2D, root: Node):
	_reset_state()
	if _room_configs.is_empty():
		push_error("RoomMgr: 无房间配置")
		return
	_player = player
	_root = root
	_room_sequence = _RoomSequence.generate()
	_sequence_index = 0
	_do_switch()


func _load_room(_entrance_direction: int):
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

	_reset_state()

	var config = _pick_config()
	_current_config = config
	var room = config.scene.instantiate()
	_current_room = room
	_root.add_child(room)
	_root.move_child(room, 0)
	_doors_unlocked = false

	_spawn_wave(config, 0)
	_position_player()
	_connect_doors()

	if int(config.room_size) == 3:
		for child in room.find_children("*", "Area2D"):
			if child.get_script() == _DoorScript and child.get("is_entrance"):
				child.unlock()
				print("BOSS房: 入口门不锁，可逃离（触碰入口门跳至下一间）")
				break

	print("Room %d/%d: [%s] %s" % [_sequence_index + 1, _room_sequence.size(), _size_name(config.room_size), config.room_name])
	_sequence_index += 1


func _pick_config() -> RoomConfig:
	if _sequence_index >= _room_sequence.size():
		_sequence_index = _room_sequence.size() - 1

	var target_size = _room_sequence[_sequence_index]

	var candidates: Array[RoomConfig] = []
	for cfg in _room_configs:
		if int(cfg.room_size) == target_size:
			candidates.append(cfg)

	if candidates.is_empty():
		candidates = _room_configs.duplicate()

	var idx: int
	if candidates.size() <= 1:
		idx = 0
	else:
		idx = randi() % candidates.size()

	var chosen = candidates[idx]
	_last_config_index = _room_configs.find(chosen)
	return chosen


func _spawn_wave(config: RoomConfig, wave_index: int):
	if _spawning_wave:
		return
	_spawning_wave = true
	_pending_wave = false

	var room = _current_room
	if not is_instance_valid(room):
		_spawning_wave = false
		return

	var markers: Array[Node] = []
	var all_spawn = room.find_children("SpawnMarker*", "Marker2D", true, false)

	if wave_index == 0:
		_current_wave_index = 0
		_active_waves = config.waves.duplicate()

	var wave: Resource
	if wave_index < _active_waves.size():
		wave = _active_waves[wave_index]
	else:
		wave = null

	if wave:
		var marker_groups = _get_wave_property(wave, "spawn_marker_groups", [])
		if not marker_groups.is_empty():
			for marker in all_spawn:
				for group_name in marker_groups:
					if marker.is_in_group(group_name):
						markers.append(marker)
						break

	if markers.is_empty():
		markers = all_spawn.duplicate()

	if wave:
		var wave_enemy_count = int(_get_wave_property(wave, "enemy_count", 0))
		if wave_enemy_count > 0:
			markers.shuffle()
			var mcount = maxi(markers.size(), 1)
			for i in range(wave_enemy_count):
				var marker = markers[i % mcount]
				if not is_instance_valid(marker):
					continue
				var enemy_scene = config.enemy_pool.pick_random()
				if not enemy_scene:
					continue
				var enemy = enemy_scene.instantiate()
				enemy.global_position = marker.global_position
				room.add_child(enemy)

	elif wave_index == 0 and config.min_enemies > 0:
		var count = randi_range(config.min_enemies, config.max_enemies)
		markers.shuffle()
		var mcount = maxi(markers.size(), 1)
		for i in range(count):
			var marker = markers[i % mcount]
			if not is_instance_valid(marker):
				continue
			var enemy_scene = config.enemy_pool.pick_random()
			if not enemy_scene:
				continue
			var enemy = enemy_scene.instantiate()
			enemy.global_position = marker.global_position
			room.add_child(enemy)

	if wave_index == 0:
		if config.boss_count > 0 and not config.boss_pool.is_empty():
			var boss_marker = room.get_node_or_null("SpawnMarker_Boss")
			for _j in range(mini(config.boss_count, config.boss_pool.size())):
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

	if wave:
		var announce = _get_wave_property(wave, "announce", "")
		if not announce.is_empty():
			_show_wave_announce(announce)

	_current_wave_index = wave_index
	_spawning_wave = false


func _show_wave_announce(text: String):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(320 - 150, 180 - 40)
	label.size = Vector2(300, 80)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var layer = CanvasLayer.new()
	layer.layer = 50

	get_tree().root.add_child(layer)
	layer.add_child(label)

	var tween = create_tween()
	label.modulate = Color(1, 1, 1, 0)
	tween.tween_property(label, "modulate", Color(1, 1, 1, 1), 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.finished.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)


func _spawn_next_wave():
	var config = _get_current_config()
	if not config:
		_pending_wave = false
		return
	var next_index = _current_wave_index + 1
	if next_index < _active_waves.size():
		_pending_wave = true
		var wave = _active_waves[next_index]
		var delay = _get_wave_property(wave, "delay", 0.0)
		if delay > 0:
			var timer = get_tree().create_timer(delay, false)
			_pending_timers.append(timer)
			timer.timeout.connect(func():
				if is_instance_valid(_current_room):
					_spawn_wave(config, next_index)
				else:
					_pending_wave = false
			)
		else:
			_spawn_wave(config, next_index)


func _get_wave_property(wave: Resource, prop: String, default_value):
	var v = wave.get(prop)
	if v == null:
		return default_value
	return v


func _get_current_config() -> RoomConfig:
	return _current_config


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


func _connect_doors():
	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			if not child.player_entered.is_connected(_on_door_entered):
				child.player_entered.connect(_on_door_entered)


func _process(_delta):
	if _doors_unlocked:
		return
	if not is_instance_valid(_current_room):
		return
	if _transitioning:
		return

	var enemy_count = EntityRegistry.get_enemy_count()

	_check_wave_triggers(enemy_count)

	if enemy_count <= 0 and not _pending_wave:
		if _current_wave_index + 1 < _active_waves.size():
			_spawn_next_wave()
		elif not _wave_broadcasted:
			_wave_broadcasted = true
			EventManager.room_cleared.emit(str(_get_current_config().room_size))
			_unlock_doors()


func _check_wave_triggers(current_enemies: int):
	if _spawning_wave or _pending_wave:
		return
	if _current_wave_index + 1 >= _active_waves.size():
		return

	var next_wave = _active_waves[_current_wave_index + 1]
	var should_trigger = false

	match _get_wave_property(next_wave, "trigger", 0):
		0:  # ON_START
			should_trigger = _current_wave_index == 0

		1:  # ENEMIES_LEFT
			var threshold = _get_wave_property(next_wave, "trigger_value", 0.0)
			if threshold > 0:
				should_trigger = current_enemies <= int(threshold)

		2:  # TIMER
			pass

	if should_trigger:
		_spawn_next_wave()


func _on_room_cleared(_room_id: String):
	pass


func _unlock_doors():
	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			child.unlock()
	_doors_unlocked = true


func _on_door_entered(door_direction: int):
	if _current_config and int(_current_config.room_size) == 3:
		print("--- 逃离BOSS房 ---")
	_load_room(door_direction)


func _size_name(s: int) -> String:
	match s:
		0: return "SMALL"
		1: return "MEDIUM"
		2: return "LARGE"
		3: return "BOSS"
	return "?"


func _tile_size(tml: TileMapLayer) -> int:
	if tml and tml.tile_set:
		return tml.tile_set.tile_size.x
	return 16
