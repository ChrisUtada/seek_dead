extends Node2D

@onready var _player: Node2D = $Player


func _ready():
	if _player:
		RoomManager.enter_first_room(_player, self)


func _exit_tree():
	GameManager.end_run()


func _input(event):
	if event.is_action_pressed("save_game"):
		_save_game()
	if event.is_action_pressed("load_game"):
		_load_game()


func _save_game():
	if not _player:
		return
	var data = {
		"hp": _player.state.hp,
		"max_hp": _player.state.max_hp,
		"energy": _player.state.energy,
		"stamina": _player.state.stamina,
		"heat": _player.state.heat,
		"position_x": _player.position.x,
		"position_y": _player.position.y,
		"weapon_index": _player.weapon.current_index,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	if SaveSystem.save_game(data):
		print("存档成功")
	else:
		push_error("存档失败")


func _load_game():
	var data = SaveSystem.load_game()
	if data.is_empty():
		print("没有存档")
		return
	if not _player:
		return
	_player.state.hp = data.get("hp", _player.state.max_hp)
	_player.state.energy = data.get("energy", _player.state.max_energy)
	_player.state.stamina = data.get("stamina", _player.state.max_stamina)
	_player.state.heat = data.get("heat", 0.0)
	_player.position = Vector2(data.get("position_x", 320.0), data.get("position_y", 180.0))
	var wi = data.get("weapon_index", 0)
	if wi < _player.weapon.get_weapon_count():
		_player.weapon.switch_weapon(wi)
	print("读档成功")
