class_name CharmData
extends Resource

# 护符（被动，整局生效）。在 _confirm_loadout 时结算为本局加成。
@export var item_id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var icon: String = "🔮"          # 展示用 emoji
@export var effect: String = ""          # damage_bonus / room_shield / interference_resist / purify_bonus
@export var value: int = 0               # 效果数值
