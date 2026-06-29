class_name EquipmentBase
extends Resource

@export var equipment_name: String = ""
@export var slot: EquipmentEnums.EquipmentSlot
@export var rarity: EquipmentEnums.Rarity = EquipmentEnums.Rarity.COMMON
@export var stat_modifiers: Array[StatModifier] = []
@export var set_id: String = ""
@export var icon: Texture2D
