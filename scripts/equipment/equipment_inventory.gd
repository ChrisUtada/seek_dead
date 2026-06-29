class_name EquipmentInventory
extends Node

signal item_added(item: EquipmentBase, index: int)
signal item_removed(item: EquipmentBase, index: int)
signal inventory_changed()

var items: Array[EquipmentBase] = []
var max_items: int = 12


func add_item(item: EquipmentBase) -> bool:
	if items.size() >= max_items:
		return false
	items.append(item)
	item_added.emit(item, items.size() - 1)
	inventory_changed.emit()
	return true


func remove_item(index: int) -> EquipmentBase:
	if index < 0 or index >= items.size():
		return null
	var item = items[index]
	items.remove_at(index)
	item_removed.emit(item, index)
	inventory_changed.emit()
	return item


func has_space() -> bool:
	return items.size() < max_items


func get_item(index: int) -> EquipmentBase:
	if index < 0 or index >= items.size():
		return null
	return items[index]


func get_item_count() -> int:
	return items.size()


func clear():
	items.clear()
	inventory_changed.emit()
