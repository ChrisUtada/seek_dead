class_name ItemData
extends Resource

# 可携带物品（统一原「消耗品」与「护符」两类）。
# - active  = 战斗中主动使用，按 charges 次数消耗（原 ConsumableData）
# - passive = 整备装配，整局被动生效（原 CharmData）
# 战斗逻辑仍按 active/passive 分流到 selected_consumables / selected_charms，
# 故保留 item_id/effect/value/charges 等字段名，确保零逻辑改动。

@export var item_id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var icon: String = "🧪"          # 展示用 emoji
@export var category: String = "active"  # active / passive
@export var effect: String = ""          # 主动: purify/heal/assault/reroll；被动: damage_bonus/room_shield/interference_resist/purify_bonus
@export var value: int = 0               # 效果数值
@export var charges: int = 1             # 主动物品每房可用次数（开局回满）；被动物品忽略
