extends Node

## 游戏全局状态管理器
## 使用 Autoload 单例模式，全局可访问

signal game_paused
signal game_resumed
signal level_changed(level_index: int)

var player_data: Dictionary = {}
var current_level: int = 1
var is_paused: bool = false
var player: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[GameManager] Initialized")

func pause_game():
	if not is_paused:
		is_paused = true
		get_tree().paused = true
		game_paused.emit()
		print("[GameManager] Game paused")

func resume_game():
	if is_paused:
		is_paused = false
		get_tree().paused = false
		game_resumed.emit()
		print("[GameManager] Game resumed")

func change_level(level_index: int):
	current_level = level_index
	level_changed.emit(level_index)
	print("[GameManager] Level changed to: %d" % level_index)

func register_player(p: Node):
	player = p
	print("[GameManager] Player registered: %s" % p.name)

var _hitstop_timer: float = 0.0

func _process(delta):
	if _hitstop_timer > 0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0:
			get_tree().paused = false

func hit_stop(duration: float = 0.04):
	if _hitstop_timer > 0:
		return
	_hitstop_timer = duration
	get_tree().paused = true

func reset():
	player_data = {}
	current_level = 1
	is_paused = false
	player = null
	get_tree().paused = false
	print("[GameManager] Reset")
