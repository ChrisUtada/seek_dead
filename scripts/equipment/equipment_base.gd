class_name EquipmentBase
extends Resource

@export var equipment_name: String = ""
@export var slot: EquipmentEnums.EquipmentSlot
@export var rarity: EquipmentEnums.Rarity = EquipmentEnums.Rarity.MAGIC
@export var affixes: Array[Affix] = []
@export var set_id: String = ""
@export var icon: Texture2D
@export var level: int = 1
@export var weapon_data: WeaponData = null  # 仅 WEAPON 槽有值
