class_name EquipmentPool
extends Resource

@export var entries: Array[EquipmentTemplate]


func roll(slot_filter: int = -1) -> EquipmentTemplate:
	var pool = entries
	if slot_filter >= 0:
		pool = pool.filter(func(e): return e.slot == slot_filter)
		if pool.is_empty():
			return null
	var total = 0.0
	for e in pool:
		total += e.weight
	if total <= 0.0:
		return null
	var r = randf() * total
	for e in pool:
		r -= e.weight
		if r <= 0.0:
			return e
	return pool.back()
