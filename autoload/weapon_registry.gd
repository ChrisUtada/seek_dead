extends Node

var _weapons: Dictionary = {}

func _ready():
	_load_all()

func _load_all():
	var dir = DirAccess.open("res://resources/weapons")
	if not dir:
		push_error("WeaponRegistry: 无法打开 resources/weapons/")
		return
	dir.list_dir_begin()
	var file = dir.get_next()
	while file:
		if file.ends_with(".tres"):
			var weapon = load("res://resources/weapons/" + file) as WeaponBase
			if weapon:
				_weapons[weapon.weapon_name] = weapon
		file = dir.get_next()

func get_weapon(name: String) -> WeaponBase:
	return _weapons.get(name)

func get_all() -> Array[WeaponBase]:
	var result: Array[WeaponBase] = []
	for w in _weapons.values():
		result.append(w)
	return result

func get_by_type(type: WeaponBase.WeaponType) -> Array[WeaponBase]:
	var result: Array[WeaponBase] = []
	for w in _weapons.values():
		if w.weapon_type == type:
			result.append(w)
	return result

func get_names() -> Array[String]:
	return _weapons.keys()
