extends Node

signal game_paused
signal game_resumed
signal level_changed(level_index: int)

enum GameState { MENU, LOADING, PLAYING, PAUSED, GAME_OVER }

var player_data: Dictionary = {}
var current_level: int = 1
var player: Node = null
var run_gold: int = 0

var _state: GameState = GameState.MENU
var _prev_state: GameState = GameState.MENU
var _hitstop_timer: float = 0.0

var _bullet_pool: ObjectPool = null


func get_bullet_pool() -> ObjectPool:
	if not _bullet_pool:
		_bullet_pool = ObjectPool.new(preload("res://scenes/battle/projectile.tscn"), 30)
	return _bullet_pool


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta):
	if _hitstop_timer > 0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0:
			get_tree().paused = false


# ===================== State Machine =====================

func change_state(new_state: GameState):
	_exit_state(_state)
	_prev_state = _state
	_state = new_state
	_enter_state(_state)


func _enter_state(s: GameState):
	match s:
		GameState.PLAYING:
			get_tree().paused = false
		GameState.PAUSED:
			get_tree().paused = true
			game_paused.emit()
		GameState.GAME_OVER:
			get_tree().paused = true
		GameState.MENU:
			reset()


func _exit_state(s: GameState):
	match s:
		GameState.PAUSED:
			game_resumed.emit()
		GameState.LOADING:
			pass


func is_state(s: GameState) -> bool:
	return _state == s


# ===================== Public API =====================

func pause_game():
	if _state == GameState.PLAYING:
		change_state(GameState.PAUSED)


func resume_game():
	if _state == GameState.PAUSED:
		change_state(GameState.PLAYING)


func start_game():
	change_state(GameState.LOADING)


func on_game_loaded():
	change_state(GameState.PLAYING)


func game_over():
	change_state(GameState.GAME_OVER)


func change_level(level_index: int):
	current_level = level_index
	level_changed.emit(level_index)


func register_player(p: Node):
	player = p


func start_run():
	run_gold = 0


func end_run():
	if run_gold > 0:
		var data = SaveSystem.load_lobby_data()
		data["gold"] = data.get("gold", 0) + run_gold
		SaveSystem.save_lobby_data(data)
		SaveSystem.flush_lobby_data()
		Debug.log("[运行结束] 金币 %d → 大厅" % run_gold)
	run_gold = 0


func hit_stop(duration: float = 0.04):
	if _hitstop_timer > 0:
		return
	_hitstop_timer = duration
	get_tree().paused = true


func reset():
	end_run()
	player_data = {}
	current_level = 1
	player = null
	get_tree().paused = false
