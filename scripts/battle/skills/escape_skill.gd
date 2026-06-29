class_name EscapeSkill
extends SkillBase

signal channel_started(duration: float)
signal channel_progress(ratio: float)
signal channel_cancelled()
signal channel_completed()

var _is_channeling: bool = false
var _channel_time: float = 0.0
var _channel_duration: float = 5.0
var _user: Node2D

func _init():
	skill_name = "紧急撤离"
	skill_description = "引导5秒后逃离当前房间，受伤或再次使用取消（CD 90秒）"
	energy_cost = 0.0
	cooldown = 90.0


func can_use(state: StateComponent) -> bool:
	if _is_channeling:
		return false
	return cooldown_timer <= 0.0


func use(user: Node2D) -> bool:
	if _is_channeling:
		_cancel_channel()
		return false
	var state = user.get("state") as StateComponent
	if not state or not can_use(state):
		return false
	_user = user
	_is_channeling = true
	_channel_time = 0.0
	user.player_damaged.connect(_on_player_damaged, CONNECT_ONE_SHOT)
	channel_started.emit(_channel_duration)
	return true


func tick(delta: float):
	if _is_channeling:
		_channel_time += delta
		channel_progress.emit(_channel_time / _channel_duration)
		if _channel_time >= _channel_duration:
			_complete_channel()
	else:
		super(delta)


func _complete_channel():
	if not _is_channeling:
		return
	_is_channeling = false
	if _user and _user.player_damaged.is_connected(_on_player_damaged):
		_user.player_damaged.disconnect(_on_player_damaged)
	cooldown_timer = cooldown
	channel_completed.emit()
	RoomManager.escape_current_room()
	_user = null


func _on_player_damaged(_amount: float, _current_hp: float, _max_hp: float):
	_cancel_channel()


func _cancel_channel():
	if not _is_channeling:
		return
	_is_channeling = false
	if _user and _user.player_damaged.is_connected(_on_player_damaged):
		_user.player_damaged.disconnect(_on_player_damaged)
	channel_cancelled.emit()
	_user = null
