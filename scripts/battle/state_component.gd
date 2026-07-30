class_name StateComponent
extends Node

signal hp_changed(current: float, max_value: float, delta: float)
signal energy_changed(current: float, max_value: float, delta: float)
signal stamina_changed(current: float, max_value: float, delta: float)
signal heat_changed(current: float, max_value: float, delta: float)
signal died()
signal stamina_depleted()
signal stamina_low()
signal heat_warning()
signal meltdown_triggered()
signal meltdown_ended()

@export var max_hp: float = 100.0
@export var max_energy: float = 100.0
@export var max_stamina: float = 100.0
@export var max_heat: float = 100.0

@export var hp_regen: float = 0.0
@export var energy_regen: float = 5.0
@export var stamina_regen: float = 10.0
@export var stamina_recover_delay: float = 1.0
@export var stamina_low_threshold: float = 5.0
@export var heat_cooling: float = 8.0
@export var heat_warning_threshold: float = 75.0
@export var meltdown_duration: float = 4.0
@export var heat_cool_delay: float = 1.0
@export var move_speed: float = 160.0
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0
@export var crit_rate: float = 0.05
@export var crit_damage: float = 1.5

var hp: float: set = _set_hp
var energy: float: set = _set_energy
var stamina: float: set = _set_stamina
var heat: float: set = _set_heat

var _stamina_recover_timer: float = 0.0
var _prev_stamina_state: int = 0
var _heat_cool_timer: float = 0.0
var _in_meltdown: bool = false
var _meltdown_timer: float = 0.0
var _prev_heat_state: int = 0

var innate_type: int = -1
var defenses: Dictionary = {}
var bonuses: Dictionary = {}

func _ready():
	hp = max_hp
	energy = max_energy
	stamina = max_stamina
	heat = 0.0

func _physics_process(delta):
	if hp > 0 and hp < max_hp:
		hp += hp_regen * delta
	if energy < max_energy:
		energy += energy_regen * delta
	if _stamina_recover_timer > 0:
		_stamina_recover_timer -= delta
	elif stamina < max_stamina:
		stamina += stamina_regen * delta
	if _in_meltdown:
		_meltdown_timer -= delta
		if _meltdown_timer <= 0:
			_end_meltdown()
		return
	if _heat_cool_timer > 0:
		_heat_cool_timer -= delta
	elif heat > 0:
		heat -= heat_cooling * delta

func _set_hp(value: float):
	var old = hp
	hp = clamp(value, 0, max_hp)
	hp_changed.emit(hp, max_hp, hp - old)
	if hp <= 0:
		died.emit()

func _set_energy(value: float):
	var old = energy
	energy = clamp(value, 0, max_energy)
	energy_changed.emit(energy, max_energy, energy - old)

func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_recover_timer = stamina_recover_delay
	return true

func _set_stamina(value: float):
	var old = stamina
	stamina = clamp(value, 0, max_stamina)
	stamina_changed.emit(stamina, max_stamina, stamina - old)
	var new_state = 2 if stamina <= 0 else (1 if stamina <= stamina_low_threshold else 0)
	if new_state != _prev_stamina_state:
		_prev_stamina_state = new_state
		match new_state:
			1: stamina_low.emit()
			2: stamina_depleted.emit()

func add_heat(amount: float):
	if _in_meltdown:
		return
	heat += amount
	_heat_cool_timer = heat_cool_delay

func _set_heat(value: float):
	var old = heat
	heat = clamp(value, 0, max_heat)
	heat_changed.emit(heat, max_heat, heat - old)
	if _in_meltdown:
		return
	if heat >= max_heat:
		_in_meltdown = true
		_meltdown_timer = meltdown_duration
		meltdown_triggered.emit()
	else:
		var new_state = 2 if heat >= heat_warning_threshold else 1 if heat > 0 else 0
		if new_state != _prev_heat_state:
			_prev_heat_state = new_state
			if new_state == 2:
				heat_warning.emit()

func _end_meltdown():
	_in_meltdown = false
	heat = 0.0
	_prev_heat_state = 0
	meltdown_ended.emit()

func in_meltdown() -> bool:
	return _in_meltdown

func is_heat_warning() -> bool:
	return not _in_meltdown and heat >= heat_warning_threshold and heat < max_heat

func get_heat_ratio() -> float:
	return heat / max_heat if max_heat > 0 else 0.0

func take_damage(amount: float, damage_type: int) -> Dictionary:
	var defender_stats = CombatStats.from_dict(defenses)
	defender_stats.innate_type = innate_type
	var attacker_stats = CombatStats.from_dict(bonuses)

	var result = DamageSystem.calculate(attacker_stats, defender_stats, damage_type, amount)
	self.hp -= result.final_damage
	return result

func get_normalized_hp() -> float:
	return hp / max_hp if max_hp > 0 else 0.0

func get_normalized_energy() -> float:
	return energy / max_energy if max_energy > 0 else 0.0

func get_normalized_stamina() -> float:
	return stamina / max_stamina if max_stamina > 0 else 0.0

func get_normalized_heat() -> float:
	return heat / max_heat if max_heat > 0 else 0.0

func is_alive() -> bool:
	return hp > 0

func reset():
	hp = max_hp
	energy = max_energy
	stamina = max_stamina
	heat = 0.0
	_stamina_recover_timer = 0.0
	_prev_stamina_state = 0
	_heat_cool_timer = 0.0
	_in_meltdown = false
	_meltdown_timer = 0.0
	_prev_heat_state = 0
