extends Node

const _DoorScript = preload("res://scripts/rooms/door_marker.gd")
const _RoomSequence = preload("res://scripts/rooms/room_sequence.gd")

const ROOM_CENTER := Vector2(320, 180)                # 640×360 视口中心，见 project.godot:34-35
const DROP_CENTER := ROOM_CENTER + Vector2(0, 20)     # 掉落物兜底落点：房间中心下方一点

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

# 子组件：波次生成与拾取物生成，由 _ready 实例化并 add_child（同上一份 HUD 拆分模式）
var _wave_spawner: WaveSpawner = WaveSpawner.new()
var _pickup_spawner: PickupSpawner = PickupSpawner.new()


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wave_spawner.init(self)
	_pickup_spawner.init(self)
	add_child(_wave_spawner)
	add_child(_pickup_spawner)
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
	EventManager.enemy_died.connect(_pickup_spawner.on_enemy_died)


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
			"res://resources/rooms/room_3_medium.tres",
			"res://resources/rooms/room_4_large.tres",
			"res://resources/rooms/room_boss.tres",
		]
		for p in fallback:
			var cfg = load(p) as RoomConfig
			if cfg and cfg.scene:
				_room_configs.append(cfg)


func _reset_state():
	_wave_spawner.reset_state()
	_current_config = null
	if is_instance_valid(_current_room):
		var p = _current_room.get_parent()
		if p:
			p.remove_child(_current_room)
	_current_room = null


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

	_wave_spawner.spawn_wave(config, 0)
	if randf() < 0.2 and config.room_size != RoomConfig.RoomSize.BOSS:
		_pickup_spawner.spawn_enchantment_table()
	_position_player()
	_connect_doors()

	Debug.log("Room %d/%d: [%s] %s" % [_sequence_index + 1, _room_sequence.size(), _size_name(config.room_size), config.room_name])
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
	return chosen


func _position_player():
	var spawn = _current_room.find_child("PlayerSpawn", true, false)
	if spawn:
		_player.global_position = spawn.global_position
		return
	var tml = _current_room.find_child("TileMapLayer") as TileMapLayer
	if tml:
		var r = tml.get_used_rect() as Rect2i
		_player.global_position = Vector2(r.get_center()) * _tile_size(tml)
	else:
		_player.global_position = ROOM_CENTER


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
	_wave_spawner.process_waves(enemy_count)


func _on_room_cleared(_room_id: String):
	if not _current_config:
		return
	# 先开门：即使后续奖励生成异常，也保证玩家不会被卡在已清的房间
	_unlock_doors()

	var count = _current_config.reward_count
	var bonus = _current_config.reward_quality_bonus
	var min_rarity = -1
	if int(_current_config.room_size) == 3:
		min_rarity = EquipmentEnums.Rarity.RARE
	var items = EquipmentDrop.generate_drops(count, bonus, min_rarity)
	_pickup_spawner.spawn_rewards(items)

	if randf() < 0.5:
		_pickup_spawner.show_skill_upgrade()


func _unlock_doors():
	for child in _current_room.find_children("*", "Area2D"):
		if child.get_script() == _DoorScript:
			child.unlock()
	_doors_unlocked = true


func _on_door_entered(door_direction: int):
	# 清房后任意方向的门都通向序列中的下一房间；BOSS 房额外记录日志
	var is_boss = _current_config and int(_current_config.room_size) == 3
	if is_boss:
		Debug.log("--- 逃离BOSS房 ---")
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


# —— 共享状态访问器（供 WaveSpawner / PickupSpawner 读取；也保留对外公共 API）——
func get_current_room() -> Node2D:
	return _current_room


func get_current_config() -> RoomConfig:
	return _current_config


func get_player() -> Node2D:
	return _player


func get_room_center() -> Vector2:
	return ROOM_CENTER


func get_drop_center() -> Vector2:
	return DROP_CENTER


func get_current_room_size() -> int:
	if not _current_config:
		return 0
	return int(_current_config.room_size)


func get_current_wave_index() -> int:
	return _wave_spawner.get_current_wave_index()


func escape_current_room():
	if _transitioning:
		return
	Debug.log("--- 紧急撤离 ---")
	_load_room(0)
