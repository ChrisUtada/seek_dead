class_name GoldUpgradeDef
extends Resource

# S12 局内金币升级定义（resources/config/gold_upgrades/*.tres，ResourceScan 扫描收集，加新升级零代码）。
# 每级花费 = base + lvl * step；max 为满级等级；效果倍率/描述由 effect + per_level 数据驱动（T3 4 轨道收敛版）。

@export var id: String = ""      # power|line|shield|hp_max（对应 effect 结算分支）
@export var effect: String = ""  # power|line|shield|hp_max（结算分支）
@export var per_level: float = 0.0   # 每级增量（power/shield/hp_max 为整数加值）
@export var bind: String = "training"  # training|reel（来源叙事；原 charm/weapon 动态轨道已退役）
@export var icon: String = ""
@export var name: String = ""
@export var base: int = 0        # 1 级花费
@export var step: int = 0        # 每级花费递增量
@export var max: int = 0         # 满级等级
