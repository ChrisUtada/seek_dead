class_name SynergyData
extends Resource

# 装备共鸣（Synergy）：自由组合的条件效果层（不限于同元素）。
# 数据驱动：resources/synergies/*.tres，ResourceScan 扫描收集，加共鸣零代码。
#
# 匹配语义（定死，勿改）：
# - 候选物品 = selected_loadout（武器）+ selected_charms（护符）
# - require_paths：精确路径，全部必须在场（AND）
# - require_tags：条件标签（"key:value"），每个标签至少被 1 件候选匹配（AND）
#   · element:X   —— 物品 element 字段 == X（fire/ice/poison/light/dark/none）
#   · category:X  —— 物品 category 字段 == X（weapon/passive）
#   · rarity:X    —— 物品 rarity 字段 == X（common/uncommon/rare/epic）
#   · type:melee|ranged —— WeaponData.weapon_type
# - 去重后的命中物品数 >= require_count 才激活
# - require_paths 与 require_tags 全空时永不激活（防御）

@export var id: String = ""                    # 唯一 id（供日志/UI 引用）
@export var name: String = ""
@export var icon: String = ""
@export var desc: String = ""
@export var require_paths: Array[String] = []  # 精确路径（AND）
@export var require_tags: Array[String] = []   # 条件标签（每标签 ≥1 命中，AND）
@export var require_count: int = 2             # 去重命中物品数阈值

# —— 效果（可叠加；激活上限由 SynergySystem 的激活集管理）——
@export var weight_bonus: Dictionary = {}      # 符号 resource_path -> 额外权重（注入 _build_strips 聚合）
@export var crit_bonus: float = 0.0            # 暴击倍率加成（触发暴击时叠加到 crit_mult）
@export var chain_bonus: int = 0               # 连锁上限加成（CHAIN_MAX + bonus）
@export var element_boost: String = ""         # 受惠元素（如 "fire"；空 = 不生效）
@export var element_boost_mult: float = 1.2    # 该元素克制倍率乘算（如 ×1.5 → ×1.8）
