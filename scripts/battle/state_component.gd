class_name StateComponent
extends Node

signal hp_changed(current: float, max_value: float, delta: float)
signal energy_changed(current: float, max_value: float, delta: float)
signal stamina_changed(current: float, max_value: float, delta: float)
signal heat_changed(current: float, max_value: float, delta: float)
signal died()

@export var max_hp: float = 100.0
@export var max_energy: float = 100.0
@export var max_stamina: float = 100.0
@export var max_heat: float = 100.0

@export var hp_regen: float = 0.0
@export var energy_regen: float = 5.0
@export var stamina_regen: float = 10.0
@export var heat_cooling: float = 8.0

var hp: float: set = _set_hp
var energy: float: set = _set_energy
var stamina: float: set = _set_stamina
var heat: float: set = _set_heat

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
	if stamina < max_stamina:
		stamina += stamina_regen * delta
	if heat > 0:
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

func _set_stamina(value: float):
	var old = stamina
	stamina = clamp(value, 0, max_stamina)
	stamina_changed.emit(stamina, max_stamina, stamina - old)

func _set_heat(value: float):
	var old = heat
	heat = clamp(value, 0, max_heat)
	heat_changed.emit(heat, max_heat, heat - old)

func take_damage(amount: float, damage_type: int) -> Dictionary:
	var defender_stats = {
		"innate_type": innate_type,
	}
	for key in defenses:
		defender_stats[key] = defenses[key]

	var attacker_stats = {}
	for key in bonuses:
		attacker_stats[key] = bonuses[key]

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
