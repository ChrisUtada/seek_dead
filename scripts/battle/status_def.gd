class_name StatusDef
extends Resource

# T23 状态定义（resources/statuses/*.tres，ResourceScan 扫描收集，加新状态零代码）。
# 状态符号（symbols/*.tres，kind=="status"）负责「触发」，状态数值/显示以本定义为唯一来源——
# 后续 status_bomb 等 BOSS 新状态直接加 .tres，不再依赖符号属性。

@export var id: String = ""           # burn|frost|poison（符号 status_type 与之对应）
@export var name: String = ""         # 显示名（燃|霜|毒，替代原 STATUS_NAMES 硬编码）
@export var icon: String = ""         # 状态图标（转轮符号旁/状态栏显示）
@export var base: float = 0.0         # 每层每回合基础伤害（DoT）
@export var element: String = "none"  # DoT 克制元素（burn→fire / frost→ice / poison→poison，走单向克制环）
@export var decay: int = 1            # 每回合层数衰减
@export var max_cols: int = 0         # 功能状态上限（frost：冻结转轮列数上限，0 = 不限制/无功能）
@export var desc: String = ""         # 说明文案
