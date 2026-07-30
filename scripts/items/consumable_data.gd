class_name ConsumableData
extends Resource

# 消耗品（战斗中主动使用）。每房按 charges 回满。
@export var item_id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var icon: String = "🧪"          # 展示用 emoji
@export var effect: String = ""          # purify / heal / assault / reroll
@export var value: int = 0               # 效果数值
@export var charges: int = 1             # 每房可用次数（开局回满）
