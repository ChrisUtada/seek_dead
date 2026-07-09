class_name LootTable
extends Resource

@export var entries: Array[LootEntry]


func roll() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry in entries:
		if randf() < entry.weight:
			var amount = randi_range(entry.min_amount, entry.max_amount)
			results.append({
				"type": entry.item_type,
				"amount": amount,
				"quality_bonus": entry.quality_bonus,
				"equip_template": entry.equip_template,
			})
	return results
