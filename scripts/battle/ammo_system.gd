class_name AmmoSystem
extends Node

signal ammo_changed(current: int, max_capacity: int)
signal reload_started()
signal reload_finished()
signal ammo_empty()

@export var max_ammo: int = 30
@export var reload_time: float = 2.0

var current_ammo: int
var is_reloading: bool = false
var _reload_timer: float = 0.0

func _ready():
	current_ammo = max_ammo

func consume_ammo() -> bool:
	if is_reloading:
		return false
	if current_ammo <= 0:
		ammo_empty.emit()
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
