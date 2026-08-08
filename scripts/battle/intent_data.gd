class_name IntentData
extends Resource

# T20 意图定义（resources/intents/*.tres，加意图 = 加 .tres + 首次出现时补执行分支）。
# 行为仍在代码侧（duel_controller 按 id 分发，与 gimmick 同模式）；本资源承载定义：
# 显示名/图标/权重/可净化/数值公式参数。默认三档表（按房型 kind）见 duel_controller.DEFAULT_INTENT_WEIGHTS；
# 房间想特化 → RoomData.intents 填自己的 Array[IntentData]（空 = 按 kind 取默认表）。

@export var id: String = ""            # attack|heavy|jam|lock|chaos|cell_lock|...
@export var display_name: String = ""  # 显示名（替代 intent_names 覆盖补丁）
@export var icon: String = ""          # ⚔ 💥 ☣ 🔒 🌀 ...
@export var desc: String = ""          # 悬浮提示用描述
@export var weight: float = 1.0        # 房间表内相对权重（RoomData.intents 使用；默认表权重见 DEFAULT_INTENT_WEIGHTS）
@export var purifiable: bool = false   # 净化药剂可否抵消（替代硬编码名单）
@export var value_mult: float = 1.0    # 数值公式参数（heavy=2.0 → 伤害 atk×2）
@export var duration: int = 1          # 持续/延迟回合（倒计时注废 timed_jam=3 预留）
