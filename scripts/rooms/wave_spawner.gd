class_name WaveSpawner
extends Node
## 波次触发与敌人（含 Boss / 精英）生成。由 RoomManager（autoload）实例化并 add_child。
## init(rm) 注入 RoomManager，以读取当前房间 / 配置 / 中心常量等共享状态。
## process_waves(enemy_count) 由 RoomManager._process 每帧调用；清房后通过
## EventManager.room_cleared 广播，由 RoomManager._on_room_cleared 统一协调奖励与开门。

var _rm: Node = null

# —— 波次状态（原 room_manager 内部状态）——
var _active_waves: Array[WaveConfig] = []
var _current_wave_index: int = 0
var _spawning_wave: bool = false
var _pending_wave: bool = false
var _pending_timers: Array = []
var _wave_broadcasted: bool = false
var _timer_waves_started: Dictionary = {}
var _current_bosses: Array[Node2D] = []


func init(rm: Node):
	_rm = rm


func reset_state():
	_clear_pending_timers()
	_active_waves.clear()
	_current_wave_index = 0
	_spawning_wave = false
	_pending_wave = false
	_wave_broadcasted = false
	_timer_waves_started.clear()
	_current_bosses.clear()


func _clear_pending_timers():
	_pending_wave = false
	_pending_timers.clear()


func get_current_wave_index() -> int:
	return _current_wave_index


## 由 RoomManager._process 每帧调用：检查波次触发，并在清房后广播 room_cleared。
func process_waves(enemy_count: int):
	_check_wave_triggers(enemy_count)
	if enemy_count <= 0 and not _pending_wave:
		if _current_wave_index + 1 < _active_waves.size():
			_spawn_next_wave()
		elif not _wave_broadcasted:
			_wave_broadcasted = true
			var cfg = _rm.get_current_config()
			if cfg:
				EventManager.room_cleared.emit(str(cfg.room_size))


func spawn_wave(config: RoomConfig, wave_index: int):
	if _spawning_wave:
		return
	_spawning_wave = true
	_pending_wave = false

	var room = _rm.get_current_room()
	if not is_instance_valid(room):
		_spawning_wave = false
		return

	var markers: Array[Node] = []
	var all_spawn = room.find_children("SpawnMarker*", "Marker2D", true, false)

	if wave_index == 0:
		_current_wave_index = 0
		_active_waves = config.waves.duplicate()

	var wave: WaveConfig
	if wave_index < _active_waves.size():
		wave = _active_waves[wave_index]
	else:
		wave = null

	if wave:
		var marker_groups = wave.spawn_marker_groups
		if not marker_groups.is_empty():
			for marker in all_spawn:
				for group_name in marker_groups:
					if marker.is_in_group(group_name):
						markers.append(marker)
						break

	if markers.is_empty():
		markers = all_spawn.duplicate()

	if wave:
		if wave.enemy_count > 0:
			_spawn_enemies_at_markers(room, markers, wave.enemy_count, config.enemy_pool)
	elif wave_index == 0 and config.min_enemies > 0:
		var count = randi_range(config.min_enemies, config.max_enemies)
		_spawn_enemies_at_markers(room, markers, count, config.enemy_pool)

	if wave_index == 0:
		if config.boss_count > 0 and not config.boss_pool.is_empty():
			var boss_marker = room.find_child("SpawnMarker_Boss", true, false)
			for _j in range(mini(config.boss_count, config.boss_pool.size())):
				var boss_scene = config.boss_pool.pick_random()
				if not boss_scene:
					continue
				var boss = boss_scene.instantiate()
				if boss_marker:
					boss.global_position = boss_marker.global_position
				else:
					var pspawn = room.find_child("PlayerSpawn", true, false)
					boss.global_position = (pspawn.global_position + Vector2(0, -80)) if pspawn else _rm.get_room_center()
				room.add_child(boss)
				_current_bosses.append(boss)

		if config.has_elite and not config.elite_pool.is_empty():
			var elite_scene = config.elite_pool.pick_random()
			if elite_scene:
				var elite = elite_scene.instantiate()
				var marker = markers[randi() % markers.size()] if markers.size() > 0 else null
				if marker:
					elite.global_position = marker.global_position
				else:
					var pspawn = room.find_child("PlayerSpawn", true, false)
					elite.global_position = (pspawn.global_position + Vector2(0, -60)) if pspawn else _rm.get_room_center()
				elite.add_to_group("elite")
				room.add_child(elite)

	if wave:
		var announce = wave.announce
		if not announce.is_empty():
			_show_wave_announce(announce)

	_current_wave_index = wave_index
	_spawning_wave = false


## 在给定 marker 列表上循环生成 count 个敌人；marker 不足时按索引取模复用。
func _spawn_enemies_at_markers(room: Node, markers: Array[Node], count: int, enemy_pool: Array):
	if markers.is_empty() or count <= 0:
		return
	markers.shuffle()
	var mcount = maxi(markers.size(), 1)
	for i in range(count):
		var marker = markers[i % mcount]
		if not is_instance_valid(marker):
			continue
		var enemy_scene = enemy_pool.pick_random()
		if not enemy_scene:
			continue
		var enemy = enemy_scene.instantiate()
		enemy.global_position = marker.global_position
		room.add_child(enemy)


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
	var config = _rm.get_current_config()
	if not config:
		_pending_wave = false
		return
	var next_index = _current_wave_index + 1
	if next_index < _active_waves.size():
		_pending_wave = true
		var wave = _active_waves[next_index]
		var delay = wave.delay
		if delay > 0:
			var timer = get_tree().create_timer(delay, false)
			_pending_timers.append(timer)
			timer.timeout.connect(func():
				if is_instance_valid(_rm.get_current_room()):
					spawn_wave(config, next_index)
				else:
					_pending_wave = false
			)
		else:
			spawn_wave(config, next_index)


func _check_wave_triggers(current_enemies: int):
	if _spawning_wave or _pending_wave:
		return
	if _current_wave_index + 1 >= _active_waves.size():
		return

	var config = _rm.get_current_config()
	if not config:
		return

	var next_wave = _active_waves[_current_wave_index + 1]
	var should_trigger = false
	var wave_index = _current_wave_index + 1

	match next_wave.trigger:
		0:  # ON_START
			should_trigger = _current_wave_index == 0

		1:  # ENEMIES_LEFT
			var threshold = next_wave.trigger_value
			if threshold > 0:
				should_trigger = current_enemies <= int(threshold)

		2:  # TIMER
			if not _timer_waves_started.has(wave_index):
				_timer_waves_started[wave_index] = true
				_pending_wave = true
				var timeout = next_wave.trigger_value
				var timer = get_tree().create_timer(timeout, false)
				_pending_timers.append(timer)
				timer.timeout.connect(func():
					if is_instance_valid(_rm.get_current_room()):
						spawn_wave(config, wave_index)
				)

		3:  # BOSS_PHASE
			var threshold = next_wave.trigger_value
			_clear_dead_bosses()
			for boss in _current_bosses:
				if is_instance_valid(boss) and boss.has_method("get_hp_ratio"):
					if boss.get_hp_ratio() <= threshold:
						should_trigger = true
						break

	if should_trigger:
		_spawn_next_wave()


func _clear_dead_bosses():
	for i in range(_current_bosses.size() - 1, -1, -1):
		if not is_instance_valid(_current_bosses[i]):
			_current_bosses.remove_at(i)
