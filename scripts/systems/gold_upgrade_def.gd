class_name GoldUpgradeDef
extends Resource

# S12 局内金币升级定义（resources/config/gold_upgrades/*.tres，ResourceScan 扫描收集，加新升级零代码）。
# 每级花费 = base + lvl * step；max 为满级等级。效果描述文案在 shop_system.gold_upgrade_desc（按 id 分派）。

@export var id: String = ""      # power|line|joker|shield（对应 gold_upgrade_desc 分支）
@export var icon: String = ""
@export var name: String = ""
@export var base: int = 0        # 1 级花费
@export var step: int = 0        # 每级花费递增量
@export var max: int = 0         # 满级等级
