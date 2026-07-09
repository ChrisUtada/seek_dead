class_name LootEntry
extends Resource

enum ItemType { GOLD, HEAL, EQUIPMENT }

@export var item_type: ItemType
@export var weight: float = 1.0
@export var min_amount: int = 1
@export var max_amount: int = 1
@export var quality_bonus: float = 0.0
@export var equip_template: Resource
