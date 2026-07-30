class_name EquipmentPickup
extends PickupBase

var item: EquipmentBase


func setup(equip: EquipmentBase):
	item = equip
	_init_pickup()


func _build_visual():
	super._build_visual()
	var color := RarityTable.get_rarity_color(item.rarity)
	_add_orb(color, Vector2(18, 18), Vector2(-9, -9))
	_add_border(Color(1, 1, 1, 0.3), Vector2(22, 22), Vector2(-11, -11))
	_add_label("?", Vector2(18, 18), Vector2(-9, -7), 12)


func _apply_effect(target: Node2D) -> bool:
	var inv := target.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if not inv:
		return false
	if inv.add_item(item):
		Debug.log("[拾取] %s (%s)" % [item.equipment_name, RarityTable.get_rarity_name(item.rarity)])
		EventManager.item_picked_up.emit({"item": item})
		Collection.register_item(item)
		return true
	Debug.log("[拾取] 背包已满")
	return false
