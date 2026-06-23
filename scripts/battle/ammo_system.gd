class_name AmmoSystem
extends Node

signal ammo_changed(current: int, max_capacity: int)
signal reload_started()
signal reload_finished()
signal ammo_empty()

@export var default_max_ammo: int = 30
@export var reload_time: float = 2.0

var current_ammo: int
var max_ammo: int = 30
var is_reloading: bool = false
var _reload_timer: float = 0.0
var _current_weapon_name: String = ""
var _ammo_pool: Dictionary = {}

func _ready():
	current_ammo = max_ammo

func switch_to_weapon(weapon_name: String, weapon_max_ammo: int):
	_save_current()
	_current_weapon_name = weapon_name
	max_ammo = weapon_max_ammo
	if _ammo_pool.has(weapon_name):
		current_ammo = _ammo_pool[weapon_name]
	else:
		current_ammo = weapon_max_ammo
		_ammo_pool[weapon_name] = current_ammo
	is_reloading = false
	_reload_timer = 0.0
	ammo_changed.emit(current_ammo, max_ammo)

func _save_current():
	if _current_weapon_name != "":
		_ammo_pool[_current_weapon_name] = current_ammo

func consume_ammo() -> bool:
	if is_reloading:
		return false
	if current_ammo <= 0:
		ammo_empty.emit()
		AudioManager.play_sfx(AudioManager.SfxType.AMMO_EMPTY)
		start_reload()
		return false
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo)
	if current_ammo <= 0:
		ammo_empty.emit()
		start_reload()
	return true

func start_reload():
	if is_reloading or current_ammo >= max_ammo:
		return
	is_reloading = true
	_reload_timer = reload_time
	reload_started.emit()
	AudioManager.play_sfx(AudioManager.SfxType.RELOAD)

func _process(delta: float):
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0:
			current_ammo = max_ammo
			is_reloading = false
			ammo_changed.emit(current_ammo, max_ammo)
			reload_finished.emit()

func add_ammo(amount: int):
	current_ammo = min(current_ammo + amount, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)
	if is_reloading and current_ammo >= max_ammo:
		is_reloading = false
		reload_finished.emit()

func get_ammo_ratio() -> float:
	return float(current_ammo) / float(max_ammo) if max_ammo > 0 else 0.0
